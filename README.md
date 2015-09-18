infscroll
=========

A simple exaple of an animated, infinitely scrolling list in Stingray.
Implemented in Scaleform Studio with Lua scripts.

![](https://github.com/randrew/infscroll/wiki/demo.gif)

Usage
-----

Open the project in Stingray and hit play. You can scroll the list up and down
using the mouse wheel or the keyboard up and down arrow keys. The list is
procedurally generated. Click on items to remove them from the list. Press 'x'
on the keyboard to restore all removed items.

Features
--------

* Variable sized items

* Adding or removing items on the fly

* Animating the size of items continuously

* Actor/component reuse

* Easily adapted to scroll along any axis, as a carousel, etc.

Quick usage summary
-------------------

The main scrolling logic is implemented in scrollist_list.lua. The demo
example that uses it is in ui_main.lua, so take a look at that file for a more
detailed guide on how to use it. Here is a brief summary of what you need to do:

First, require the scrolling logic:

	local Scroller = require 'script/lua/scrolling_list'

You can use whatever local name you want, but we'll call it Scroller in this
example.

Next, you'll need to create the table of data that is used to maintain the
scrolling state. This requires passing a table of options into the creation
procedure, Scroller.create().

	{
		visible_length=function() : number,
		data_start=function() : data?,
		data_prev=function(data) : data?,
		data_next=function(data) : data?,
		data_valid=function(data) : bool,
		data_measure=function(data) : number,
		view_take=function(data) : view,
		view_release=function(view) : nil,
		view_set_data=function(view, data) : nil,
		view_set_visible=function(view, bool) : nil,
		view_set_position=function(view, number) : nil
	}

You should create a table like this where the following conditions hold:

`visible_length` is a function that takes no arguments and returns a number
representing the visible size of the list you want to scroll. For example, if
you have a vertically scrolling list that will appear on screen as 300 pixels
wide and 700 pixels tall, this function could be defined as:

	visible_length=function() return 700 end

`data_start` is a function that takes no arguments and returns the starting
value of whatever data type you will be displaying in your GUI. For example,
if you're displaying an array of strings in a list, this would return the
index of the first string in the array, which is probably 1. You can also
return nil if there is nothing to display.

	data_start=function() if #my_array > 0 then return 1 else return nil end

`data_prev` and `data_next` are iterator functions which take as an argument
the same type of data returned by your `data_start` function and return the
previous or next data item in the sequence, or nil if there aren't any more in
that direction.

	data_prev=function(x) if my_array[x-1] then return x-1 else return nil end

	data_next=function(x) if my_array[x+1] then return x+1 else return nil end

If your array is not contiguous, you will need to implement this differently.
See ui_main.lua for an example.

`data_valid` is a function which takes the same type of data as `data_prev` or
`data_next` and returns true (or some other truthy value) or false (or nil)
representing if the item is still valid. This is the function that the
scrolling list logic will use to determine when to remove items that are
already visible.

	data_valid=function(x) return my_array[x] end

`data_measure` takes one of your data items as a argument and returns the
visible length or size of the data item in the direction that the list
scrolls. For example, if you have a list of images and you are displaying them
in a vertical list, then this function will return the height of the image.

	data_measure=function(x) return x.height end

`view_take` is a function which takes as a single argument of one of your data
items and returns some other type which represents a view on screen which can
then be used to display the data item. For example, the argument might be an
index of an image in an array, and the type your function returns might be a
Scaleform Actor with an image component on it.

The value you return to be used to view the data item must be *available*, in
the sense that nothing else can already be using it to display data. In our
imaginary example of displaying images in a list, we would either need to
create a new Scaleform actor and image component and return them each time
this is called, or instead we could *pool* them and only create new ones if we
run out of items in the pool. This pooling behavior is made possible by the
next function we must implement:

`view_release` is a function which takes as a single argument the same type of
data returned by your `view_take` function, and returns nothing. You do not
need to make this do anything unless you are pooling your view types, but it's
recommended that you do so.

Examples of `view_take` and `view_release` with pooling behavior can be found
in ui_main.lua.

`view_set_data` is a function which takes two arguments, a view, and a data to
display. Your code is responsible for doing the rest. This is likely where you
would take your view actor and set properties on its components to display
what's in your data.

	view_set_data=function(view, data)
		scaleform.TextComponent.set_text(view.text_component, data.my_text)
		...
	end

`view_set_visible` is a function which takes two arguments, a view, and
whether or not it should be visible at all. You should use this function to
add or remove your Actors from whatever container you are putting them in
within the Scaleform stage.

`view_set_position` is a function which takes two arguments, a view, and a
number which is its location in the list along the direction it scrolls. You
should use this function to set the position of your Actors within their
container.

	view_set_position=function(view, position)
		scaleform.Actor.set_local_position(view.actor, {x=0, y=position})
	end

Updating
--------

Call Scroller.update() every frame. Your code is also in charge of handling
input and calling Scroller.scroll_by() to actually make things scroll. See
ui_main.lua for an example

Bugs
----

It's probably full of them. This is my first time making something with Lua
and Stingray/Scaleform Studio.

TODO
----

* More documentation
* Scrollbars
* Automated testing
* Change to use Lua-style 'class' calls (with :)?