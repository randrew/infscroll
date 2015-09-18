local Utils = require 'script/lua/utils'
local Actor = scaleform.Actor
local Component = scaleform.Component
local ContainerComponent = scaleform.ContainerComponent
local ShapeComponent = scaleform.ShapeComponent

local RectMask = {}

function RectMask.create(target_actor)
	local parent = Actor.parent(target_actor)
	local container = Actor.container(parent)
	local actor, shape = Actor.create(container, ShapeComponent)
	Actor.set_mask_actor(target_actor, actor)
	return {
		target_actor_weakref=Utils.weak_ref(target_actor),
		container=container,
		mask_actor=actor,
		shape=shape
	}
end

function set_mask_size(mask, x, y)
	Actor.set_dimensions(mask.mask_actor, scaleform.Size({width=x, height=y}))
	ShapeComponent.clear(mask.shape)
	ShapeComponent.set_fill(mask.shape,0xFFFFFF, 1)
	ShapeComponent.draw_rect(mask.shape, {x=0, y=0, width=x, height=y})
end

function RectMask.set_size(mask, x, y)
	local dims = Actor.dimensions(mask.mask_actor)
	if dims.width ~= x or dims.height ~= y then
		set_mask_size(mask, x, y)
	end
end

function RectMask.destroy(mask)
	ShapeComponent.clear(mask.shape)
	local target_actor = mask.target_actor_weakref()
	if target_actor then
		Actor.set_mask_actor(target_actor, nil)
	end
	local parent = Actor.parent(mask.mask_actor)
	if parent then
		local container = Actor.container(parent)
		if container then
			ContainerComponent.remove_actor(container, mask.mask_actor)
		end
	end
end

return RectMask