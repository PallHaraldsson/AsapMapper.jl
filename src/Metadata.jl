################################################################################
# Components - Processors, Memory, IO Handlers
################################################################################

# Task classes are used to control which tasks are mapped to which cores.
# each core has fulfill one or more task classes. Each task will be assigned a
# class and will be mapped to a core that supports that task.
"All task classes currently recognized by the Mapper."
const _mapper_task_classes = Set([
      "processor",
      "memory_processor",
      "input_handler",
      "output_handler",
      "memory_1port",
      "memory_2port",
    ])

# Special attributes are task attributes that are considere "sparse" in the
# architecture and should be moved direct look-up tables rather than 
# near-address search
const _special_attributes = Set([
      "memory_processor",
      "input_handler",
      "output_handler",
      "memory_1port",
      "memory_2port",
    ])

# Function to unify mapper types cleanly between tasks and cores.
memory_meta(ports::Int) = "memory_$(ports)port"
ismemory(s::String) = startswith(s, "memory") && endswith(s, "port")
ismemory(x) = false

# Global NT for dealing with attributes.
const MTypes = @NT(
    proc        = "processor",
    memoryproc  = "memory_processor",
    input       = "input_handler",
    output      = "output_handler",
    memory      = memory_meta,
    # Experimental high-performance vs low-power processor cores.
    lowpower   = "low_power",
    highperformance = "high_performance",
)

typekey() = "mapper_type"

ismappable(c::AbstractComponent)    = haskey(c.metadata, typekey())

isproc(c::AbstractComponent)        = ismappable(c) && in(MTypes.proc, c.metadata[typekey()])
ismemoryproc(c::AbstractComponent)  = ismappable(c) && in(MTypes.memoryproc, c.metadata[typekey()])
isinput(c::AbstractComponent)       = ismappable(c) && in(MTypes.input, c.metadata[typekey()])
isoutput(c::AbstractComponent)      = ismappable(c) && in(MTypes.output, c.metadata[typekey()])
islowpower(c::AbstractComponent)     = ismappable(c) && in(MTypes.lowpower, c.metadata[typekey()])
ishighperformance(c::AbstractComponent) = ismappable(c) && in(MTypes.highperformance, c.metadata[typekey()])

function ismemory(c::AbstractComponent)
    ismappable(c) || return false
    for i in c.metadata[typekey()]
        if ismemory(i)
            return true
        end
    end
    return false
end

################################################################################
# Assignment of metadata to Components.
################################################################################
proc_metadata() = Dict{String,Any}(typekey() => [MTypes.proc])
mem_proc_metadata() = Dict{String,Any}(typekey() => [MTypes.proc, MTypes.memoryproc])

function mem_nport_metadata(nports::Int)
    attrs = [MTypes.memory(i) for i in 1:nports]
    return Dict{String,Any}(
        typekey() => attrs,
        # Options for plotting
        "shadow_offset" => [Address(0,i) for i in 1:nports-1],
        "fill"          => "memory"
    )
end

input_handler_metadata() = Dict{String,Any}(typekey() => [MTypes.input])
output_handler_metadata() = Dict{String,Any}(typekey() => [MTypes.output])

add_lowpower(c::Component) = push!(c.metadata[typekey()], MTypes.lowpower)
add_highperformance(c::Component) = push!(c.metadata[typekey()], MTypes.highperformance)

################################################################################
# Metadata for Taskgraph Nodes
################################################################################

const TN = TaskgraphNode
# Setting task -> core requirements.
make_input!(t::TN)       = (t.metadata[typekey()] = MTypes.input)
make_output!(t::TN)      = (t.metadata[typekey()] = MTypes.output)
make_proc!(t::TN)        = (t.metadata[typekey()] = MTypes.proc)
make_memoryproc!(t::TN)  = (t.metadata[typekey()] = MTypes.memoryproc)
make_memory!(t::TN, ports::Integer) = t.metadata[typekey()] = MTypes.memory(ports)
# low-power high-performance stuff
make_lowpower(t::TN) = (t.metadata[typekey()] = MTypes.lowpower)
make_highperformance(t::TN) = (t.metadata[typekey()] = MTypes.highperformance)

# Getting task -> core requirements.
ismappable(t::TN)   = true
isinput(t::TN)      = t.metadata[typekey()] == MTypes.input
isoutput(t::TN)     = t.metadata[typekey()] == MTypes.output
isproc(t::TN)       = t.metadata[typekey()] == MTypes.proc
ismemoryproc(t::TN) = t.metadata[typekey()] == MTypes.memoryproc
ismemory(t::TN)     = ismemory(t.metadata[typekey()])
# low-power high performance stuff
islowpower(t::TN) = t.metadata[typekey()] == MTypes.lowpower
ishighperformance(t::TN) = t.metadata[typekey()] == MTypes.highperformance

# Setting task -> core preference.
mutable struct TaskRank
    # Ranks
    rank                    ::Union{Float64,Missing}
    normalized_rank         ::Float64
end
TaskRank(rank) = TaskRank(rank, 0)

mutable struct CoreRank
    rank                    ::Union{Float64,Missing}
    normalized_rank         ::Float64
end
CoreRank(rank) = CoreRank(rank, 0)

# Make these generic so they work on Components and TaskgraphNodes.
getrank(t) = get(t.metadata, "rank", missing)
setrank!(t, val) = t.metadata["rank"] = val

################################################################################
# Routing Resources
################################################################################

"Routng link types currently implemented in the Mapper."
const _mapper_link_classes = Set([
        "circuit_link",
        "memory_request_link",
        "memory_response_link",
    ])

# Generic function for making a metadata dictionary for ports/links where only
# the link-class is needed.
function routing_metadata(link_class)
    if !in(link_class, _mapper_link_classes)
        throw(KeyError(link_class))
    end

    return Dict{String,Any}(
        "link_class" => link_class,
    ) 
end

# Processor component metadata.
function proc_output_metadata(ndirs, nlayers)
    metadata_vec = map(1:(ndirs * nlayers)) do i
        return Dict{String,Any}(
            "link_class"    => "circuit_link",
            "index"         => i-1,
            "network_id"    => div(i-1, ndirs),
        )
    end
    return metadata_vec
end

function proc_fifo_metadata(nfifos)
    metadata_vec = map(1:nfifos) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1
        )
    end
    return metadata_vec
end

function proc_memory_request_metadata()
    return Dict{String,Any}(
        "link_class" => "memory_request_link",
        "index" => 0
    )
end

function proc_memory_return_metadata()
    return Dict{String,Any}(
        "link_class" => "memory_response_link",
        "index" => 0
    )
end

# Memories
function mem_memory_request_metadata(nports)
    metadata_vec = map(1:nports) do i
        return Dict{String,Any}(
            "link_class" => "memory_request_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

function mem_memory_return_metadata(nports)
    metadata_vec = map(1:nports) do i
        return Dict{String,Any}(
            "link_class" => "memory_response_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

# io handlers
function input_handler_port_metadata(nlinks)
    metadata_vec = map(1:nlinks) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1,
        )
    end
end

function output_handler_port_metadata(nlinks)
    metadata_vec = map(1:nlinks) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

################################################################################
# Metadata for top level ports - used for pretty post-route plotting.

function top_level_port_metadata(orientation, direction, class, num_links)
    # Get a base dictionary for this port class.
    base = routing_metadata(class)
    # Parameters controlling offset generation.
    x_spacing = 0.4/num_links
    y_spacing = 0.4/num_links

    if orientation in ("east", "west")
        if direction == "input" 
            if orientation == "east"
                x_offset = 1.0
                y_offset = 0.05
            else
                x_offset = 0.0
                y_offset = 0.55
            end
        else
            if orientation == "east"
                x_offset = 1.0
                y_offset = 0.55
            else
                x_offset = 0.0
                y_offset = 0.05
            end
        end
        # Dictionary creation
        offset_dicts = map(0:num_links-1) do i
            # Make a dict with some offset values
            d = Dict(
                "x" => x_offset,
                "y" => y_offset + i*y_spacing
               ) 
            # merge with the base metadata dictionary
            return merge(d, base)
        end
    elseif orientation in ("north", "south")
        if direction == "input" 
            if orientation == "north"
                x_offset = 0.05
                y_offset = 0.0
            else
                x_offset = 0.55
                y_offset = 1.0
            end
        else
            if orientation == "north"
                x_offset = 0.55
                y_offset = 0.0
            else
                x_offset = 0.05
                y_offset = 1.0
            end
        end
        # Dictionary creation
        offset_dicts = map(0:num_links-1) do i
            # Make a dict with some offset values
            d = Dict(
                "x" => x_offset + i*x_spacing,
                "y" => y_offset,
               ) 
            # merge with the base metadata dictionary
            return merge(d, base)
        end
    else
        offset_dicts = [base for i in 1:num_links]
    end
    return offset_dicts
end


################################################################################
# Miscellaneous data
################################################################################

# Functions for making port-offsets. Allows nicer plotting of routes.
function make_port_metadata(direction, class, num_links)
    x_spacing = 0.4/num_links
    y_spacing = 0.4/num_links
    if direction in ("east", "west")
        if class == "input" 
            if direction == "east"
                x_offset = 1.0
                y_offset = 0.05
            else
                x_offset = 0.0
                y_offset = 0.55
            end
        else
            if direction == "east"
                x_offset = 1.0
                y_offset = 0.55
            else
                x_offset = 0.0
                y_offset = 0.05
            end
        end
        return [Dict("x" => x_offset, "y" => y_offset + i * y_spacing) 
                    for i in 0:num_links-1]
    elseif direction in ("north", "south")
        if class == "input" 
            if direction == "north"
                x_offset = 0.05
                y_offset = 0.0
            else
                x_offset = 0.55
                y_offset = 1.0
            end
        else
            if direction == "north"
                x_offset = 0.55
                y_offset = 0.0
            else
                x_offset = 0.05
                y_offset = 1.0
            end
        end
        return [Dict("x" => x_offset + i * x_spacing, "y" => y_offset) 
                    for i in 0:num_links-1]
    else
        return [make_port_metadata() for _ in 1:num_links]
    end
end

make_port_metadata() = Dict("x" => 0.5, "y" => 0.5)
make_port_metadata(num_links) = [make_port_metadata() for _ in 1:num_links]