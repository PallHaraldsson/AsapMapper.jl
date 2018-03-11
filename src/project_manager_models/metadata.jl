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


function proc_metadata() 
    return Dict{String,Any}(
        "attributes" => ["processor"],
    )
end

function mem_proc_metadata() 
    return Dict{String,Any}(
        "attributes" => ["processor", "memory_processor"],
    )
end

function mem_nport_metadata(nports::Int)
    attrs = ["memory_$(i)port" for i in 1:nports]
    return Dict{String,Any}(
        "attributes" => attrs,
    )
end

function input_handler_metadata()
    return Dict{String,Any}(
        "attributes" => ["input_handler"],
    )
end

function output_handler_metadata()
    return Dict{String,Any}(
        "attributes" => ["output_handler"],
    )
end

################################################################################
# Routing Resources
################################################################################

"Routng link types currently implemented in the Mapper."
const _mapper_link_classes = Set([
        "circuit_link",
        "memory_request_link",
        "memory_return_link",
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
function proc_output_metadata(nports)
    metadata_vec = map(1:nports) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1,
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
        "link_class" => "memory_return_link",
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
            "link_class" => "memory_return_link",
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