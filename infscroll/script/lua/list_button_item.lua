
local Item = {}

function Item.create()
	local new_butt = scaleform.Actor.load("item_button.s2dactor")
	local label_actor = scaleform.Actor.actor_by_name_path(new_butt, "label")
	local image_actor = scaleform.Actor.actor_by_name_path(new_butt, "block")
	local text_component = scaleform.Actor.component_by_index(label_actor, 1)

	scaleform.TextComponent.set_selectable(text_component, false)
	scaleform.TextComponent.set_editable(text_component, false)
	return {
		actor=new_butt,
		label_actor=label_actor,
		label_component=text_component,
		image_actor=image_actor,
		container=scaleform.Actor.container(new_butt)
	}
end

function Item.set_hovered(item, bool)
	local cx = nil
	if bool then
		cx = scaleform.Cxform.create_tint(0.5, 0.4, 0.6, 0.9)
	else
		cx = scaleform.Cxform.create()
	end
	scaleform.Actor.set_cxform(item.image_actor, cx)
end

function Item.set_alphas(item, base_alpha, text_alpha)
	scaleform.Actor.set_cxform(item.actor, scaleform.Cxform.create_alpha(base_alpha))
	scaleform.Actor.set_cxform(item.label_actor, scaleform.Cxform.create_alpha(text_alpha))
end

function Item.destroy(item)
	local parent = scaleform.Actor.parent(item.actor)
	if parent then
		local container = scaleform.Actor.container(parent)
		if container then
			scaleform.ContainerComponent.remove_actor(item.actor)
		end
	end
end

function Item.set_text(item, text)
	scaleform.TextComponent.set_text(item.label_component, text)
end

return Item