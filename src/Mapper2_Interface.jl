#=
Function overloads and custom types for interacting with Mapper2.

Specifically:

    - Defines attributes in the architectural model and how that relates to
        mappability.

    - Custom placement TwoChannel edge that contains a "cost" field for
        annotating important links. Also provides a custom "edge_cost" method
        for this new type of link.

    - Custom routing channel with a cost field.
=#

################################################################################
# Custom architectural definitions for Mapper2
################################################################################

const TN = TaskgraphNode
const TE = TaskgraphEdge

function Mapper2.ismappable(::Type{<:KC}, c::Component)
    return haskey(c.metadata, typekey()) && length(c.metadata[typekey()]) > 0
end

function Mapper2.isspecial(::Type{<:KC}, t::TN)
    return in(t.metadata[typekey()], _special_attributes)
end

function Mapper2.isequivalent(::Type{<:KC}, a::TN, b::TN)
    # Return true if the "mapper_type" are equal
    return a.metadata[typekey()] == b.metadata[typekey()]
end

function Mapper2.canmap(::Type{<:KC}, t::TN, c::Component)
    haskey(c.metadata, typekey()) || return false
    return in(t.metadata[typekey()], c.metadata[typekey()])
end

function Mapper2.is_source_port(::Type{<:KC}, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    return port_link_class == edge_link_class
end

function Mapper2.is_sink_port(::Type{<:KC}, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    # Check if this is a circuit_link. If so, preserve the destination index.
    if (e.metadata["preserve_dest"] && port_link_class == edge_link_class)
        return e.metadata["dest_index"] == p.metadata["index"]
    end

    return port_link_class == edge_link_class
end

function Mapper2.needsrouting(::Type{<:KC}, edge::TaskgraphEdge)
    return edge.metadata["route_link"]
end

################################################################################
# Placement
################################################################################

# All edges for KC types will be "CostEdge". Even if the profiled_links option
# is not being used, links between memories and memory_processors will still
# be given a higher weight to encourage them to be mapped together.
#
# The main difference here is the "cost" field, which will be multiplied by
# the distance between nodes to emphasize some connections over others.
struct CostEdge <: Mapper2.SA.TwoChannel
    source ::Int64
    sink   ::Int64
    cost   ::Float64
end

# Extend the "edge_cost" function for KC types.
function Mapper2.SA.edge_cost(::Type{<:KC}, sa::SAStruct, edge::CostEdge)
    src = getaddress(sa.nodes[edge.source])
    dst = getaddress(sa.nodes[edge.sink])
    return  edge.cost * sa.distance[src, dst]
end

# Constructor for CostEdges. Extracts the "cost" field from the metadata
# of each taskgraph edge type.
function Mapper2.SA.build_channels(::Type{<:KC}, edges, sources, sinks)
    return map(zip(edges, sources, sinks)) do x
        edge,srcs,snks = x

        # Quick verification that no fanout is happening. This should never
        # happen for normal KiloCore mappings.
        @assert length(srcs) == 1
        @assert length(snks) == 1

        # Since all the source and sink vectors are of length 1, we can get the
        # source and sink simply by taking the first element.
        source = first(srcs)
        sink = first(snks)
        cost = edge.metadata["cost"]
        return CostEdge(source,sink,cost)
    end
end

# ------------------------------------------ #
# Extensions for Frequency Variation Mapping #
# ------------------------------------------ #

# The main idea with frequency mapping is that each node has a normalized
# ranking between 0 and 1. The auxiliary objective is to minimize the maximum
# ratio between node ranking and core ranking across the entire mapping.

# Ranked nodes contain their ranking (listed above) and their handle to the
# maxheap contained in the "aux" data-struct for this flavor of mapping.
#
# The maxheap allows for contant-time checking of the highest ratio between
# nodes and cores.
mutable struct RankedNode{T} <: Mapper2.SA.Node
    location    ::T
    out_edges   ::Vector{Int64}
    in_edges    ::Vector{Int64}
    # Normalized rank and derivative
    rank            ::Float64
    maxheap_handle  ::Int64
end


# Must extend the "move" and "swap" functions to update the auxiliary
# maxheap every time a node is moved for correct handling of the maximum
# task-to-core ratio.
function SA.move(sa::SAStruct{KC{true, false}}, index, spot)
    node = sa.nodes[index]
    sa.grid[SA.location(node)] = 0
    SA.assign(node, spot)
    sa.grid[SA.location(node)] = index

    # Get the rank for the core at the location of the node and update this
    # node's handle in the heap.
    component_rank = sa.address_data[SA.location(node)]
    ratio = node.rank / component_rank

    update!(sa.aux.ratio_max_heap, node.maxheap_handle, ratio)
end

function SA.swap(sa::SAStruct{KC{true, false}}, node1, node2)
    # Get references to these objects to make life easier.
    n1 = sa.nodes[node1]
    n2 = sa.nodes[node2]
    # Swap address/component assignments
    s = SA.location(n1)
    t = SA.location(n2)

    SA.assign(n1, t)
    SA.assign(n2, s)
    # Swap grid.
    sa.grid[t] = node1
    sa.grid[s] = node2

    # Compute the ratios for both nodes and update their handles in the maxheap.
    n1_ratio = n1.rank / sa.address_data[SA.location(n1)]
    n2_ratio = n2.rank / sa.address_data[SA.location(n2)]
    update!(sa.aux.ratio_max_heap, n1.maxheap_handle, n1_ratio)
    update!(sa.aux.ratio_max_heap, n2.maxheap_handle, n2_ratio)

    return nothing
end

# Constructor for RankedNodes.
function Mapper2.SA.build_node(::Type{KC{true, false}}, n::TaskgraphNode, x)
    rank = getrank(n).normalized_rank
    handle = n.metadata["heap_handle"]
    # Initialize all nodes to think they are the max ratio. Code for first move
    # operation will figure out which one is really the maximum.
    return RankedNode(x, Int64[], Int64[], rank, handle)
end

# Get the address data for each node.
function Mapper2.SA.build_address_data(::Type{KC{true,false}}, c::Component)
    rank = getrank(c).normalized_rank
    return rank
end

# Global auxiliary cost for frequency mapping.
#
# Take the maximum ratio from the top of the ratio max heap and apply the
# penalty term to it.
function Mapper2.SA.aux_cost(::Type{KC{true,false}}, sa::SAStruct)
    return sa.aux.task_penalty_multiplier * top(sa.aux.ratio_max_heap)
end

# ----------------------------------- #
# Extensions for Heterogenous Mapping #
# ----------------------------------- #

# Use an enum to encode nodes by their class. Non-processor nodes will recieve
# a "neutral" class and not be penalized. Don't bother marking "high_performance"
# nodes as they can only be mapped to high_performance cores.
@enum NodeClass low_power neutral

mutable struct HeterogenousNode{T} <: Mapper2.SA.Node
    location    :: T
    out_edges   :: Vector{Int64}
    in_edges    :: Vector{Int64}
    # Keep track of the type of the node
    class       :: NodeClass
end

function Mapper2.SA.build_node(::Type{KC{false,true}}, n::TaskgraphNode, x)
    if islowpower(n)
        class = low_power
    else
        class = neutral
    end

    return HeterogenousNode(x, Int64[], Int64[], class)
end

# Extend the "address_cost" method to penalize low_power tasks mapped to non
# low_power components.
function Mapper2.SA.address_cost(::Type{KC{false,true}}, sa::SAStruct, node::SA.Node)
    if node.class == neutral
        return zero(Float64)

    # If this entry in the "address_data" struct is "false", this is not a low
    # power location.
    elseif !sa.address_data[SA.location(node)]
        return zero(Float64)

    # Otherwise, we have a low_power node mapped to a non-low_power component.
    else
        # TODO: Make this a variable penalty
        return 5.0
    end
end

# Return a boolean if this component is a low_power component. This is used
# to penalize mappings where low_power nodes are mapped to non-low_power 
# components
function Mapper2.SA.build_address_data(::Type{KC{false,true}}, c::Component)
    return islowpower(c)
end


################################################################################
# Routing
################################################################################

# Custom Channels
struct CostChannel <: AbstractRoutingChannel
    start_vertices   ::Vector{Vector{Int64}}
    stop_vertices    ::Vector{Vector{Int64}}
    cost             ::Float64
end

Base.isless(a::CostChannel, b::CostChannel) = a.cost < b.cost

function Mapper2.routing_channel(::Type{<:KC}, start, stop, edge)
    cost = edge.metadata["cost"]
    return CostChannel(start, stop, cost)
end
