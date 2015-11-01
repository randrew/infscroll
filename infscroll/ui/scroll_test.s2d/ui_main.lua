local Utils = require 'script/lua/utils'
local Scroller = require 'script/lua/scrolling_list'
local ListItem = require 'script/lua/list_button_item'
local RectMask = require 'script/lua/rect_mask'

local Actor = scaleform.Actor
local Component = scaleform.Component
local ContainerComponent = scaleform.ContainerComponent
local AnimationComponent = scaleform.AnimationComponent

-- These will be set in the start() procedure. We cannot access Scaleform's
-- stage at this point in time.
local child_container, this_actor, mask

local anim_out_time = 0.45
local container_size = {width=200, height=600}
local removed_indices = {}
local fading_out_indices = {}
local highlighted_view = nil

-- Views
local view_pool = {}

local function view_take(idx)
	if #view_pool > 0 then
		return table.remove(view_pool, #view_pool)
	else
		return ListItem.create()
	end
end

local function view_destroy(v)
	ListItem.destroy(v)
end

local function view_release(v)
	table.insert(view_pool, v)
end

local function index_measure(state)
	local n = state % 4
	local base = 45 + n * 20
	local age = fading_out_indices[state]
	if age then
		return Utils.lerp(base, 0, math.pow(age / anim_out_time, 0.5))
	else
		return base
	end
end

local function view_set_size_and_alpha(v, idx)
	local height = index_measure(idx)
	local size = scaleform.Size()
	size.width = container_size.width
	size.height = height
	Actor.set_dimensions(v.image_actor, size)

	local age = fading_out_indices[idx]
	local base_alpha, text_alpha
	if age then
		base_alpha = Utils.clamp(1 - math.pow(age / (anim_out_time / 1.3), 1.75), 0, 1)
		text_alpha = Utils.clamp(1 - math.pow(age / (anim_out_time / 5), 2), 0, 1)
	else
		base_alpha = 1
		text_alpha = 1
	end
	ListItem.set_alphas(v, base_alpha, text_alpha)
end

local function view_set_visible(view, is_visible)
	if is_visible then
		ContainerComponent.add_actor(child_container, view.actor)
	else
		ContainerComponent.remove_actor(child_container, view.actor, false)
	end
end

local function view_set_position(view, position)
	Actor.set_local_position(view.actor, {x=0, y=position})
end

-- Indices
local function string_for_index(idx)
	return "Item " .. tostring(idx)
end

local function index_valid(idx)
	assert(idx, "datum thing is not nil")
	return idx > 0 and (not removed_indices[idx])
end

local function set_state(v, idx)
	if idx then
		assert(index_valid(idx), "datum is valid")
		view_set_size_and_alpha(v, idx)
		ListItem.set_text(v, string_for_index(idx))
	else
		ListItem.set_text(v, "?")
	end
end

local function index_start()
	for i=1,1000 do
		if not removed_indices[i] then
			return i
		end
	end
	return nil
end

local function index_prev(idx)
	local i = idx - 1
	while i > 0 do
		if not removed_indices[i] then return i end
		i = i - 1
	end
	return nil
end

local function index_next(idx)
	local i = idx + 1
	while true do
		if not removed_indices[i] then return i end
		i = i + 1
	end
	return nil
end

local scrolling_list = Scroller.create{
	visible_length=function() return container_size.height end,
	data_start=index_start,
	data_prev=index_prev,
	data_next=index_next,
	data_valid=index_valid,
	data_measure=index_measure,
	view_take=view_take,
	view_release=view_release,
	view_set_data=set_state,
	view_set_visible=view_set_visible,
	view_set_position=view_set_position
}

local function point_in_size(p, size)
	return p.x >= 0 and p.x < size.width and p.y >= 0 and p.y < size.height
end

local function update(dt)
	RectMask.set_size(mask, container_size.width, container_size.height)

	local up_id = stingray.Mouse.button_id("wheel_down")
	local down_id = stingray.Mouse.button_id("wheel_up")
	local mouse_up = stingray.Mouse.pressed(up_id)
	local mouse_down = stingray.Mouse.pressed(down_id)
	local keyboard_up = Utils.is_key_down("down")
	local keyboard_down = Utils.is_key_down("up")
	local mouse_scroll_speed = 20
	local keyboard_scroll_speed = 500 * dt

	if Utils.was_key_pressed("x") then
		removed_indices = {}
	end

	if Utils.was_key_pressed("c") then
		Scroller.scroll_to(scrolling_list, 60, {visible_position=100})
	end
	if Utils.was_key_pressed("v") then
		Scroller.scroll_to(scrolling_list, 100, {visible_position=100})
	end
	if Utils.was_key_pressed("b") then
		Scroller.scroll_to(scrolling_list, 1, {visible_position=-100})
	end
	local val = 0
	if mouse_up then
		val = mouse_scroll_speed
	elseif mouse_down then
		val = -mouse_scroll_speed
	end

	if keyboard_up then
		val = val + keyboard_scroll_speed
	end
	if keyboard_down then
		val = val - keyboard_scroll_speed
	end

	if mouse_up or mouse_down or keyboard_up or keyboard_down then
		Scroller.scroll_by(scrolling_list, val)
	end
	Scroller.update(scrolling_list, dt)

	-- update sizing animation
	local removed = {}
	for item, age in pairs(fading_out_indices) do
		fading_out_indices[item] = age + dt
		if fading_out_indices[item] > anim_out_time then
			removed_indices[item] = true
			table.insert(removed, item)
		else
			local view = Scroller.view_for_item(scrolling_list, item)
			if view then
				view_set_size_and_alpha(view, item)
			end
		end
	end
	for i=1, #removed do
		fading_out_indices[removed[i]] = nil
	end

	-- highlighting

	local cursor_pos = scaleform.Point()
	if stingray then
		local p = stingray.Mouse.axis(stingray.Mouse.axis_id("cursor"), stingray.Mouse.RAW, 3)
		-- Not sure which one is correct
		-- local w, h = stingray.Application.back_buffer_size()
		local w, h = stingray.Gui.resolution()
		cursor_pos.x = p.x
		cursor_pos.y = h - p.y
	else
		cursor_pos.x = 0
		cursor_pos.y = 0
	end

	local from_stage = scaleform.Stage.transform_to_screen_matrix()
	-- Workaround for Scaleform bug
	-- http://forums.autodesk.com/t5/stingray/scaleform-stage-transform-to-screen-matrix-return-value/td-p/5822396
	from_stage = Matrix2F.Append(Matrix2F.Identity(), from_stage)
	local to_stage = Matrix2F.Invert(from_stage)
	local cursor_pos_stage = Matrix2F.Transform(to_stage, cursor_pos)
	local mouse_local = Actor.world_to_local(this_actor, cursor_pos_stage)

	local item = nil
	if point_in_size(mouse_local, container_size) then
		item = Scroller.item_at_position(scrolling_list, mouse_local.y)
	end

	local view = nil
	if item and (not fading_out_indices[item]) then
		view = Scroller.view_for_item(scrolling_list, item)
	end
	if view ~= highlighted_view then
		if highlighted_view then
			ListItem.set_hovered(highlighted_view, false)
		end
		highlighted_view = view
		if highlighted_view then
			ListItem.set_hovered(highlighted_view, true)
		end
	end

	if item and Utils.was_mouse_clicked("left") then
		if not fading_out_indices[item] then
			fading_out_indices[item] = 0
		end
	end
end

GlobalUI = GlobalUI or {}

function GlobalUI.start()
	local list = scaleform.Stage.actor_by_name_path("Scene0.list")
	local list_container = Actor.container(list)
	this_actor, child_container = Actor.create(list_container, ContainerComponent)
	mask = RectMask.create(this_actor)
end

function GlobalUI.update(dt)
	update(dt)
end

function GlobalUI.shutdown()
	Scroller.reset(scrolling_list)
	ContainerComponent.remove_actor(child_container, this_actor)
end
