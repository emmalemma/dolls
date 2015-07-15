_ = require 'lodash'
el = require './coffee-hyperscript'
h = require 'virtual-dom/virtual-hyperscript'
VText = require 'virtual-dom/vnode/vtext'
createElement = require 'virtual-dom/create-element'

me = module.exports =
	button: (suffix, label, handler)->
		if typeof label is 'function'
			handler = label
			label = suffix
			suffix = ''

		h 'button'+suffix, 'ev-click': handler, [new VText label]

	text: (suffix, props, handler)->
		if typeof suffix is 'object'
			handler = props
			props = suffix
			suffix = ''
		else if typeof props is 'function'
			handler = props
			props = {}
		else if typeof props is 'string'
			props = value: props
		if 'value' of props and typeof props.value isnt 'string'
			props.value = ''
		h 'input'+suffix, _.extend props, me.textChangeEvents handler
	
	editable: class ContentEditableWidget
		type: 'Widget'
		constructor: (selector, value, handler)->
			unless @constructor is ContentEditableWidget
				return new ContentEditableWidget selector, value, handler
			@selector = selector
			@value = value
			if typeof handler is 'object'
				@handler = handler
			else if typeof handler is 'function'
				@handler = change: handler


		init: ->
			el = createElement h @selector, {contentEditable: on}, [@value]
			el.addEventListener 'keyup', @keyup
			el.addEventListener 'keydown', @keydown
			el.addEventListener 'blur', @blur
			el

		blur: (e)=>
			e.value = e.target.innerText
			@handler.blur? e

		keyup: (e)=>
			e.value = e.target.innerText
			if e.value isnt @value
				@value = e.value
				@handler.change? e

		keydown: (e)=>
			setTimeout =>
					@keyup e
				, 0

		update: (prev, elem)->
			# @handler = prev.handler # wat
			if @selector isnt prev.selector
				@selector = prev.selector
				@init()
			else
				elem.removeEventListener 'keyup', prev.keyup
				elem.removeEventListener 'keydown', prev.keydown
				elem.removeEventListener 'blur', prev.blur
				elem.addEventListener 'keyup', @keyup
				elem.addEventListener 'keydown', @keydown
				elem.addEventListener 'blur', @blur
				if document.activeElement is elem
					sel = window.getSelection()
					offset = Math.min sel.anchorOffset, @value?.length or 0
					elem.innerText = @value
					range = document.createRange()
					range.setStart elem.firstChild or elem, offset
					sel.removeAllRanges()
					sel.addRange range
				else
					elem.innerText = @value
				elem

		destroy: (elem)->
			elem.removeEventListener 'keyup', @keyup
			elem.removeEventListener 'keydown', @keydown
			elem.removeEventListener 'blur', @blur
	
	
	file: (props, handler)->
		if typeof props is 'function'
			handler = props
			props = {}
		props.type = 'file'
		props['ev-change'] = (e)=>
			e.value = e.target.files
			handler.apply this, arguments
		h 'input', props
	
	labeled: (suffix, label, children...)->
		children.unshift h 'span', label
		h 'label', children
	
	selectProps: (suffix, props, handler)->
		mapping = {}
		if typeof suffix is 'object'
			handler = props
			props = suffix
			suffix = ''
		props ?= {}

		props['ev-change'] = (e)->
			console.log 'change', e
			return unless e.target.value 
			e.value = mapping[e.target.value] or e.target.value
			handler e

		value = props.value
		delete props.value
		label = props.label
		delete props.label

		any = no
		options = 
			_.map props.options, ([k, l, m])->
				unless l
					l = k
				if m
					mapping[k] = m
				selected = if value
					(m and value is m) or value is k
				else not m
				any or= selected
				h 'option', {value: k, selected}, [new VText l]
		delete props.options
		
		if label
			options.unshift h 'option', {value: '', selected: not any}, label

		h 'select'+suffix, props, options

	select: (label, value, options, handler)->
		mapping = {}
		if typeof options is 'function'
			handler = options
			options = value
			value = label
			label = null

		change = (e)->
			return unless e.target.value
			e.value = mapping[e.target.value] or e.target.value
			handler e
		any = no
		options = 
			_.map options, ([k, l, m])->
				unless l
					l = k
				if m
					mapping[k] = m
				selected = (m and value is m or value is k)
				any or= selected
				h 'option', {value: k, selected}, [new VText l]
		if label
			options.unshift h 'option', {value: '', selected: not any}, label


		h 'select', {'ev-change': change}, options

	textChangeEvents: (cb)->
		prevValue = null
		timeout = null
		ev =(e)->
			clearTimeout timeout
			if prevValue isnt e.target.value
				e.value = e.target.value
				cb e
			prevValue = e.target.value
		# 'ev-change': ev
		'ev-keyup': ev
		'ev-keydown': (e)->timeout = setTimeout (->ev e), 0

