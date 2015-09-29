local Utils = require 'script/lua/utils'

local Scroller = {}

local function dvmap_create()
	return {d_to_v={}, v_to_d={}}
end
local function dvmap_insert(dvmap, item, view)
	assert(not dvmap.d_to_v[item], "item already exists")
	assert(not dvmap.v_to_d[view], "view already exists")
	dvmap.d_to_v[item] = view
	dvmap.v_to_d[view] = item
end
local function dvmap_remove(dvmap, item, view)
	assert(dvmap.d_to_v[item], "item exists during remove")
	assert(dvmap.v_to_d[view], "view exists during remove")
	dvmap.d_to_v[item] = nil
	dvmap.v_to_d[view] = nil
end
local function dvmap_get_item(dvmap, view)
	return dvmap.v_to_d[view]
end
local function dvmap_get_view(dvmap, item)
	return dvmap.d_to_v[item]
end

-- Find a new origin datum and the difference in world space that will give
-- the smallest positive offset for an equivalent view.
--
-- Returns the new origin datum and the change in origin to subtract from your
-- existing offset.
--
-- e.g.,
--
-- local new_datum, c = reduce(datum, offset, ...)
-- local best_offset = offset - c
-- local do_other_stuff(new_datum, best_offset, ...)
local function reduce(datum, offset, measure_fn, prev_fn, next_fn)
	local x = datum
	local c = 0
	if offset > 0 then
		::loop::
		local c_ = c + measure_fn(x)
		if c_ > offset then goto done end
		c = c_
		local x_ = next_fn(x)
		if not x_ then goto done end
		x = x_
		goto loop
		::done::
	else
		while c > offset do
			local x_ = prev_fn(x)
			if not x_ then break end
			x = x_
			c = c - measure_fn(x)
		end
	end
	return x, c
end

-- Clamp the offset into the origin datum such that any 'empty' visible space
-- exists after the last visible item. Note that this returns a non-normalized
-- offset into the origin item, so you may need to reduce it afterwards.
local function fit_visible(datum, offset, view_length, datum_length_fn, prev_fn, next_fn)
	local o = offset
	if o >= 0 then
		local d = datum
		local headroom = 0
		while headroom < view_length + offset and d do
			headroom = headroom + datum_length_fn(d)
			d = next_fn(d)
		end
		o = math.min(headroom - view_length, offset)
	end
	if o < 0 then
		local headroom = 0
		local d = prev_fn(datum)
		while headroom > o and d do
			headroom = headroom - datum_length_fn(d)
			d = prev_fn(d)
		end
		o = math.max(headroom, o)
	end
	return o
end

-- Returns items, positions where items is an ordered array of each visible
-- item, and positions is a table of item to its visible offset in the world
local function positions(datum, offset, view_length, measure_fn, prev_fn, next_fn)
	-- Array of items that are visible. Ordered from beginning to end.
	local items = {}
	-- Map of item to visible position in the list.
	local positions = {}

	-- Reduce. When building the positions, we want to start on the item that
	-- is first in the list, and we want a positive offset into it.
	local d, c = reduce(datum, offset, measure_fn, prev_fn, next_fn)
	-- Visible offset. Negative because positive numbers are later into the
	-- container/view space.
	local o = -(offset - c)

	-- Accumulate position and insert items
	while o < view_length and d do
		table.insert(items, d)
		positions[d] = o
		o = o + measure_fn(d)
		d = next_fn(d)
	end

	return items, positions
end

-- Use the existing origin and offsets if possible, or build new ones from
-- previous calculated cosmetic data, or revert to default/start if nothing
-- else.
local function anchor(anchor_datum, items, positions, target_offset, offset, valid_fn, start_fn)
	-- Fastest and most common path: previous origin datum still exists.
	if anchor_datum and valid_fn(anchor_datum) then
		return anchor_datum, target_offset, offset
	end

	-- If our origin anchor is gone, we will attempt recover it via the
	-- results of the previous computation of positions. Incurs some loss of
	-- precision.

	for i=1,#items do
		local d = items[i]
		-- Negate because positive is further into the 'world' space, and we
		-- want the origin item + offset.
		local p = -positions[d]
		if valid_fn(d) then
			-- Because we are using positions that were based on the
			-- displayed/cosmetic offset (for scrolling animations) instead of
			-- the target ('real') offset, we need to adjust the returned
			-- target offset by the previous difference in target offset and
			-- displayed offset.
			--
			-- The cosmetic offset remains the same.
			return d, p + (target_offset - offset), p
		end
	end

	-- No recoverable context exists, revert to base
	return start_fn(), 0, 0
end

-- Return the world-space distance between 'from' and 'to'. Uses a dumb search
-- that scans linearly in each direction until finding the destination or
-- until the 'search_limit' world-space distance has been covered. Returns nil
-- if unable to find 'to'.
local function distance_search(from, to, search_limit, measure_fn, prev_fn, next_fn)
	local x = from
	-- Try searching forward.
	local o = 0
	::loop::
	if o > search_limit then goto done end
	if x == to then return o end
	o = o + measure_fn(x)
	x = next_fn(x)
	if not x then goto done end
	goto loop
	::done::
	-- Didn't find it. Try searching backward.
	o = 0
	x = prev_fn(from)
	while o < search_limit and x do
		o = o + measure_fn(x)
		if x == to then return -o end
		x = prev_fn(x)
	end
	-- Couldn't find it.
	return nil
end

-- Detach any invalid or unused views and return them to the pool. Also
-- removes any invalid items from the item list.
local function free_unused_views(dvmap, items, valid_fn, detach_fn)
	local items_set = {}
	for i=1,#items do
		items_set[items[i]] = true
	end
	local pairs_to_remove = {}
	for d, v in pairs(dvmap.d_to_v) do
		if (not items_set[d]) or (not valid_fn(d)) then
			pairs_to_remove[d] = v
		end
	end

	for d, v in pairs(pairs_to_remove) do
		detach_fn(v)
		dvmap_remove(dvmap, d, v)
	end
end

-- Create (or get from pool) views for all items
local function create_views(dvmap, items, create_fn, attach_fn)
	for i=1, #items do
		local item = items[i]
		local view = dvmap_get_view(dvmap, item)
		-- create view if it doesn't already exist for this item data
		if not view then
			view = create_fn(item)
			dvmap_insert(dvmap, item, view)
			attach_fn(view, item)
		end
	end
end

local function set_positions(dvmap, items, positions, set_pos_fn)
	for i=1, #items do
		local item = items[i]
		local view = dvmap_get_view(dvmap, item)
		local position = positions[item]
		if view and position then
			set_pos_fn(view, position)
		end
	end
end

local function process_scroll_input(scroller, dt)
	local scroll_delta = scroller.unconsumed_scroll_input

	-- Inertia should be processed every tick. This procedure contains an
	-- early return in the case that there is not enough accumulated scroll
	-- inputa delta, but the inertia should be processed before returning.
	local inertia = scroller.scroll_input_inertia
	inertia = Utils.weighted_average(inertia, 0, 0.15, dt)

	-- If there is negligible scroll input, then do not consume or process it.
	if math.abs(scroll_delta) < 0.1 then
		scroller.scroll_input_inertia = inertia
		return scroller.target_scroll_offset
	end
	-- We will process all scroll input.
	scroller.unconsumed_scroll_input = 0

	-- If the scroll input is the opposite direction of any existing scroll
	-- input inertia, then set the inertia to zero.
	if Utils.sign(scroll_delta) ~= Utils.sign(inertia) then
		inertia = 0
	end

	-- Increase inertia along the direction of the scroll input.
	inertia = inertia + (scroll_delta * scroller.discrete_inertia_fraction)
	-- Modify the input scroll delta by inertia.
	scroll_delta = scroll_delta + scroll_delta * math.abs(inertia)
	-- Set new inertia to the scrolling list state.
	scroller.scroll_input_inertia = inertia

	return scroller.target_scroll_offset + scroll_delta
end

local function tick_scroll_position(scroller, dt)
	scroller.scroll_offset = Utils.weighted_average(scroller.scroll_offset, scroller.target_scroll_offset, scroller.scrolling_interpolation_fraction, dt)
end

local function update_scroller_data(scroller)
	local length = scroller.view_size_fn()

	local function detach(view)
		scroller.view_set_visible_fn(view, false)
		scroller.set_data_fn(view, nil)
		scroller.release_view_fn(view)
	end
	local function attach(view, datum)
		scroller.set_data_fn(view, datum)
		scroller.view_set_visible_fn(view, true)
	end
	local function set_pos(view, y_offset)
		scroller.view_set_position_fn(view, y_offset)
	end

	local items, positions = positions(scroller.anchor_datum, scroller.scroll_offset, length, scroller.data_measure_fn, scroller.prev_datum_fn, scroller.next_datum_fn)

	-- Return to the pool any views which were previously visible but are now
	-- not visible.
	free_unused_views(scroller.dvmap, items, scroller.datum_is_valid_fn, detach)
	-- For each item that is newly visible, create a new view, or retrieve one
	-- from the pool.
	create_views(scroller.dvmap, items, scroller.create_view_fn, attach)
	-- For each view, call the procedure to set its visual position.
	set_positions(scroller.dvmap, items, positions, set_pos)

	scroller.previously_visible_items = items
	scroller.previously_visible_positions = positions
end

function Scroller.create(args)
	return {
		dvmap=dvmap_create(),
		previously_visible_items={},
		previously_visible_positions={},
		target_scroll_offset=0,
		scroll_offset=0,
		unconsumed_scroll_input=0,
		scroll_input_inertia=0,
		anchor_datum=nil,

		view_size_fn=args.visible_length,
		get_starting_datum_fn=args.data_start,
		prev_datum_fn=args.data_prev,
		next_datum_fn=args.data_next,
		datum_is_valid_fn=args.data_valid,
		data_measure_fn=args.data_measure,
		create_view_fn=args.view_take,
		release_view_fn=args.view_release,
		set_data_fn=args.view_set_data,
		view_set_visible_fn=args.view_set_visible,
		view_set_position_fn=args.view_set_position,

		-- TODO better names for these, docs
		discrete_inertia_fraction=args.discrete_inertia_fraction or 0.015,
		scrolling_interpolation_fraction=args.scrolling_interpolation_fraction or 0.0001
	}
end

-- Reset all state
function Scroller.reset(scroller)
	-- Remove all views that are in use (visible, has data set)
	for d, v in pairs(scroller.dvmap.d_to_v) do
		scroller.view_set_visible_fn(v, false)
		scroller.set_data_fn(v, nil)
		scroller.release_view_fn(v)
	end
	-- Reset dvmap
	scroller.dvmap = dvmap_create()
	-- Reset scroll state
	scroller.target_scroll_offset = 0
	scroller.scroll_offset = 0
	scroller.unconsumed_scroll_input = 0
	scroller.scroll_input_inertia = 0

	scroller.anchor_datum = nil
	scroller.previously_visible_items = {}
	scroller.previously_visible_positions = {}
end

-- Scroll the position of everything by 'scroll_delta'.
function Scroller.scroll_by(scroller, scroll_delta)
	scroller.unconsumed_scroll_input = scroller.unconsumed_scroll_input + scroll_delta
end

-- Make 'item' visible on screen, offset from the beginning of the container
-- view by 'visible_position'.
function Scroller.scroll_to(scroller, item, options)
	options = options or {}
	local visible_position = options.visible_position or 0
	local search_distance = options.search_distance or (4 * scroller.view_size_fn())

	local d = nil

	local measure = scroller.data_measure_fn
	local prev = scroller.prev_datum_fn
	local next = scroller.next_datum_fn
	local length = scroller.view_size_fn()

	local offset = -visible_position
	local item, c = reduce(item, offset, measure, prev, next)
	-- TODO fix fit_visible so it work even when denormalized
	offset = fit_visible(item, offset - c, length, measure, prev, next)
	item, c = reduce(item, offset, measure, prev, next)
	offset = offset - c

	if scroller.anchor_datum then
		-- TODO will jump if anchor item was removed this tick, should use anchor
		-- first.
		d = distance_search(scroller.anchor_datum, item, search_distance, measure, prev, next)
	end

	scroller.anchor_datum = item
	scroller.target_scroll_offset = offset
	if d then
		scroller.scroll_offset = scroller.scroll_offset - d
	else
		scroller.scroll_offset = offset
	end
end

-- Call this once per frame, after applying any scroll input with scroll_by or scroll_to.
function Scroller.update(scroller, dt)
	-- If the origin item has been removed, we need to recover a new origin
	-- item from the previously calculated positions of visible items. In the
	-- typical case, the origin item will not have been removed, and this
	-- procedure will simply return the existing datum, target_offset, offset.
	--
	-- The results from this procedure are not necessarily normalized in
	-- origin, offset space, which is fine, because reduction will happen later
	-- regardless.
	local datum, target_offset, offset = anchor(
		scroller.anchor_datum,
		scroller.previously_visible_items,
		scroller.previously_visible_positions,
		scroller.target_scroll_offset,
		scroller.scroll_offset,
		scroller.datum_is_valid_fn,
		scroller.get_starting_datum_fn)

	-- Update if changed
	scroller.target_scroll_offset = target_offset
	scroller.scroll_offset = offset

	local new_offset = process_scroll_input(scroller, dt)

	if datum then
		local measure = scroller.data_measure_fn
		local prev = scroller.prev_datum_fn
		local next = scroller.next_datum_fn
		local length = scroller.view_size_fn()

		-- Restrict the visible area's position such that empty space is
		-- minimized and occurs after any items.
		local fit_offset = fit_visible(datum, new_offset, length, measure, prev, next)
		local new_datum, c = reduce(datum, fit_offset, measure, prev, next)

		scroller.anchor_datum = new_datum
		scroller.target_scroll_offset = fit_offset - c
		scroller.scroll_offset = scroller.scroll_offset - c
	else
		scroller.anchor_datum = nil
	end

	tick_scroll_position(scroller, dt)
	update_scroller_data(scroller)
end

-- Get the list of visible items.
function Scroller.visible_items(scroller)
	return scroller.previously_visible_items
end

-- Get the visible item at 'position', or nil if none.
function Scroller.item_at_position(scroller, position)
	local items = scroller.previously_visible_items
	local positions = scroller.previously_visible_positions
	local measure_fn = scroller.data_measure_fn
	local valid_fn = scroller.datum_is_valid_fn
	for i=1,#items do
		local item = items[i]
		if item and valid_fn(item) then
			local p = positions[item]
			if p then
				if position >= p and position < p + measure_fn(item) then
					return item
				end
			end
		end
	end
	return nil
end

-- Get the view for visible item 'item', or nil if none.
function Scroller.view_for_item(scroller, item)
	return scroller.dvmap.d_to_v[item]
end

return Scroller