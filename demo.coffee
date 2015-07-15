'use strict'
Delegator = require 'dom-delegator'

VDom = require 'virtual-dom'
isVNode = require 'virtual-dom/vnode/is-vnode'
_ = require 'lodash'
el = require './client/coffee-hyperscript'
ui = require './client/ui'
cJSON = require 'circular-json'

h = require 'virtual-dom/virtual-hyperscript'

Immutable = require 'immutable'
toJSList =(x)->x?.toList().toJS() or []

# I'm made out of a lisp-like thing that lives inside of an immutable javascript data structure

# The data structure describes a tree (technically DAG) of computed values,
# any of which can be set while maintaining consistency of computation.

# Think of it as a visual representation not of an AST, but of the actual eval/apply tree in a running interpreter

# Not all of this works yet.

# [ fn 
# 	[[fn, 'expect the unexpected',
# 		arg: a
# 		[fn, ...]
# 		[fn, ...]
# 		(arg)->
# 			arg.matey
# 	]]
# ]


add = (a, b)-> a + b
verbs =
	el: do (el)->el = (tag, props, children)->h tag, props.toObject(), children.toArray()
	add: add 
	identity: identity = (x)->x
	quote: quote = (x)->x
	replacing: replacing = (body, name, value)->
		body.setIn name, value
	mapping: mapping = (partial, list)->
		list.map (v)->partial.push v
	mutator: mutator = (name, fn)->
		(event)->mutate name, fn
	setter: (name, value)->
		(event)->mutator name, ->value
	seqel: ->
		@default -> Immutable.Map
			tag: 'div'
			props: Immutable.Map()
			children: Immutable.List()

		tag = @get('tag')
		props = @get('props')
		children = @get('children')

		h tag, props.toObject(), children.toArray()


mapping.__macro = yes
replacing.__macro = yes
quote.__macro = yes

faces = Immutable.Map()
namesplace = Immutable.Map()
rootStack = Immutable.Stack [root] 
redoStack = Immutable.Stack [root] 

renderer = null
root = rootFace = null
faceStack = []
renderX = (x, inspect, rewrite)->
	# console.log 'rendering', x
	if x is undefined
		el 'div.undefined', 'undef'
	else if x is null
		el 'div.null', 'null'
	else 
		switch typeof x
			when 'boolean'
				el 'div.boolean',
					el 'input', 
						type: 'checkbox'
						checked: x
						onclick: ->
							rewrite not x
					x.toString()
			when 'string'
				el 'div.string', 
					el 'div.string-seperator', '"'
					ui.editable 'div.string-content', x, (e)->
						rewrite e.value
					el 'div.string-seperator', '"'
			when 'number'
				base = 10
				el 'div.number',
					el 'div.number-base', {10:'10'}[base]
					ui.editable 'div.number-digits', x.toString(base), (e)->rewrite parseInt e.value, base
			when 'function'
				body = if x.syntaxError
					x.body
				else
					x.toString()

				el 'div.function', 
					ui.selectProps '.select-verb', 
						value: x
						options: _.map verbs, (v, k)->[k, (if v.__macro then '*' else '') + k, v]
						label: "#{if x.__macro then '*' else ''}#{x.name or '[anonymous function]'}"
						(e)->rewrite e.value
					if x.syntaxError
						el 'div.error.syntax-error', x.syntaxError.message
					if inspect
						ui.editable 'div.function-body', body, (e)->
							fn = null
							try
								eval "fn = #{e.value};"
							catch error
								fn =->error
								fn.body = e.value
								fn.syntaxError = error
							if x.__macro
								fn.__macro = yes
							rewrite fn
			when 'object'
				el 'div.raw-json',
					cJSON.stringify x

toVDom = (tree)->
	unless tree?
		el 'div.null', 'null'
	else if isVNode tree
		tree
	else VDom.VText tree


currentDom = null
rootElement = null
initialize = (tree)->
	currentDom = toVDom tree
	rootElement = VDom.create currentDom
	html = VDom.create el 'html', 
		el 'head',
			el 'meta', charset: 'UTF-8'
			el 'link', res: 'stylesheet', href: 'http://fonts.googleapis.com/css?family=Play|Comfortaa|Poiret+One'
			el 'link', rel: 'stylesheet', href: 'demo.css'
		el 'body'
	document.replaceChild html, document.documentElement
	document.body.appendChild rootElement
	window._dom_delegator = Delegator()

mode = 'debug'

layout = (tree)->
	el 'div.inspector',
		className: 'wired'
		el 'div.inspector-buttons',
			el 'div.undo',
				if rootStack.size
					el 'button',
						onclick: ->
							redoStack = redoStack.push rootStack.peek()
							rootStack = rootStack.pop()
							root = rootStack.peek()
							renderer no
						'undo'
				if redoStack.size
					el 'button',
						onclick: ->
							root = redoStack.peek()
							redoStack = redoStack.pop()
							renderer yes
						'redo'
							
		tree

linkAKA = null

faces = Immutable.Map()
Face = Immutable.Record
	name: Immutable.List()
	data: null
	highlight: no
	inspect: no
	controls: no
	radialTarget: null
	radialMenu: null
	controlPoint: null

realCache = new WeakMap
realize = (data)->
	if data and typeof data is 'object' and typeof data.hashCode is 'function'
		unless realCache.has data
			do realCacheMiss =->
				realCache.set data, realized = do realizing =->
					if isApplication data
						do realizingApp =->
							try
								if isMacro data
									do realizeMacro =->
										realize data.first().apply null, data.rest().toArray()
								else
									do realizeApp =->
										realize data.first().apply null, do realizeAppArgs =->data.rest().map(realize).toArray()
							catch error
								error
					else if typeof data.hashCode is 'function'
						do mapRealize =->
							data.map realize
					else data
				realized
		else
			do getCache =->
				realCache.get data
	else
		data

isMacro = (data)-> data.first().__macro
isApplication =(data)->
	Immutable.List.isList(data) and typeof data.first() is 'function'

domCache = new WeakMap

renderFace = (name, data)->
	face = faces.get name
	unless domCache.has(face) and Immutable.is face.data, data
		do domCacheMiss =->
			aka = namesplace.get(name) or Immutable.Set.of name
			scalar = not data or typeof data not in ['object', 'function']
			face = face or new Face {name}
			face = face.set 'data', data
			domCache.set face,
				el 'div.doll-face',
					'onmouseover': ->
						unless face.highlight
							aka.forEach (name)->mutateFace name, (face)-> face.set 'highlight', yes
					'onmousedown': (e)->
						closest = e.target
						return if closest.tagName in ['INPUT', 'SELECT', 'OPTION', 'BUTTON'] or closest.contentEditable is 'true'
						e.preventDefault()
						offset = x: e.offsetX, y: e.offsetY
						while closest.parentElement and closest.className isnt 'doll-face'
							closest = closest.parentElement
						if closest is e.currentTarget
							offsetParent = e.target
							offset.x -= 10
							offset.y -= 10
							until offsetParent is e.currentTarget
								console.log offsetParent, offset
								offset.x += offsetParent.offsetLeft
								offset.y += offsetParent.offsetTop
								offsetParent = offsetParent.offsetParent
							console.log e, offset, e.offsetX, e.offsetY, closest.offsetLeft
							mutateFace name, (face)-> 
								face.set 'controls', yes 
								.set 'controlPoint', offset
								.set 'radialMenu', null
						yes
					onmouseleave: close =(e)->
						if face.controls
							console.log 'left', e
							mutateFace name, (face)-> face.set 'controls', no
						if face.highlight
							aka.forEach (name)->mutateFace name, (face)-> face.set 'highlight', no
					dollHeader name, data, face, aka
					el 'div.doll-body',
						className: if scalar then 'scalar' else ''
						do bodyDom =->
							makeDom name, data, face

			faces = faces.set name, face
	do domCacheGet =->
		domCache.get face

refName = null

dollHeader = (name, data, face, aka)->
	inspect = face?.inspect
	scalar = not data or typeof data not in ['object', 'function']
	el "div.doll-header",
		el "div.doll-eye.#{if face.highlight then 'highlight' else ''}",
			el "div.doll-eye-inner.#{if face?.highlight then 'highlight' else ''}.#{if scalar then 'small' else if not inspect then 'closed' else 'opened'}",
				className: if face.controls then 'halo' else ''
				onclick: ->
					mutateFace name, (face)-> face.set 'inspect', not face.inspect 
				style:
					backgroundColor: '#' + Math.abs(aka.hashCode()).toString(16)[0..5]
		if face?.highlight 
			el "div.doll-controls.#{if face?.controls then '' else 'hide'}",
				style:
					left: if face.controls then face.controlPoint?.x + 'px' else 0
					top: if face.controls then face.controlPoint?.y + 'px' else 0
				onmouseleave: -> 
					if face.controls
						mutateFace name, (face)-> face.set 'controls', no
				el "div.doll-controls-inner",
					el 'div.doll-controls-backdrop',
						onmouseup: -> 
							if face.controls
								mutateFace name, (face)-> face.set 'controls', no
						style:
							backgroundColor: '#' + Math.abs(aka.hashCode()).toString(16)[0..5]
					do ->
						menu = (x)->
							x._menu = yes
							x
						back = menu -> mutateFace name, (face)->
							face.set 'radialMenu', null
							.set 'controls', yes
						
						targets =
							if face.radialMenu is 'nouns'
								_.map nouns, (v, k)-> [k, if v is 'back' then back else (->mutate name, ->v)]
							else if face.radialMenu is 'meta'
								_.pairs
									'src': -> linkAKA = aka
									'back': menu -> mutateFace name, (face)->
										face.set 'radialMenu', null
										.set 'controls', yes
									'link': -> rename aka, (aka)->linkAKA.union aka
									'brk': -> rename aka, ->Immutable.Set.of name
									'ref': -> refName = name
									'deref': -> mutate name, ->refName
							else
								_.pairs
									'set': menu -> mutateFace name, (face)->
										face.set 'radialMenu', 'nouns'
										.set 'controls', yes
									'meta': menu -> mutateFace name, (face)->
										face.set 'radialMenu', 'meta'
										.set 'controls', yes
									'remove': ->unname name
						_.map targets, ([k, v], i)->
							p = targets.length / i
							x = Math.cos(2 * Math.PI / p)
							y = Math.sin(2 * Math.PI / p)
							el 'div.radial-target',
								style:
									left: "#{50 + x * 50}%"
									top: "#{50 + y * 50}%"
								onmouseover: ->
									if v._menu
										do v
									else
										mutateFace name, (face)->face.set 'radialTarget', k
								onmouseout: ->
									if face.radialTarget is k
										mutateFace name, (face)->face.set 'radialTarget', null 
								onmouseup: ->
									mutateFace name, (face)->face.set 'controls', no
									do v
								className: if face?.radialTarget is k then 'target' else ''
								k
					unless face.inspect
						k = 'inspect'
						do (k)->
							el 'div.radial-center.up',
								onmouseover: ->mutateFace name, (face)->face.set 'radialTarget', k
								onmouseout: ->
									if face.radialTarget is k
										mutateFace name, (face)->face.set 'radialTarget', null 
								className: if face?.radialTarget is k then 'target' else ''
								onmouseup: -> mutateFace name, (face)->
									face.set 'inspect', yes
									.set 'controls', no
								'inspect'
					else
						k = 'collapse'
						do (k)->
							el 'div.radial-center.down',
								onmouseover: ->mutateFace name, (face)->face.set 'radialTarget', k
								onmouseout: ->mutateFace name, (face)->face.set 'radialTarget', null if face.radialTarget is k
								className: if face?.radialTarget is k then 'target' else ''
								onmouseup: -> mutateFace name, (face)->
									face.set 'inspect', no
									.set 'controls', no
								'collapse'

nouns = 
	back: 'back'
	null: null
	boolean: true
	number: 10
	string: 'string'
	function: verbs.identity
	App: Immutable.List.of verbs.identity, yes
	List: Immutable.List()
	Map: Immutable.Map()

makeDom = (name, data, face, quote = no)->
	el 'div.doll-dom', 
		className: 'wired'
		if isVNode data
			data
		else unless data and typeof data is 'object'
			renderX data, face?.inspect, (value)->
				mutate name, ->value
		else if data instanceof Error
			el 'div.error', data.message
		else
			if (not quote) and isApplication data
				realized = do realizeApp =-> realize data
				el 'div.application',
					if isApplication realized
						do applicationFace =->
							el 'div.application-ext',
								renderFace name.push('__forward'), realized, face
					else
						do applicationDom =->
							el 'div.application-ext',
								makeDom name.push('__forward'), realized, face
					if face?.inspect
						do applicationInspect =->
							el 'div.application-int',
								makeDom name, data, face, yes
			else if Immutable.List.isList data
				if face?.inspect
					el 'div.doll-list',
						toJSList data.map listDataCache = (subData, key)->
							subFace = faces.get name.push(key)
							if subFace 
								if subFace and Immutable.is(subFace?.data, subData) and domCache.has subFace
									domCache.get subFace
								else
									do listDataCacheMiss =->
										domCache.set subFace, dom = el 'div.doll-item',
											do listItemFace =->
												renderFace name.push(key), subData
										dom
							else
								el 'div.doll-item',
									renderFace name.push(key), subData
						el 'button', 
							onclick: ->
								mutate name, (list)->
									list.push null
							'+'
				else
					el 'div.doll-list.summary', "#{data.count()} items"
			else if Immutable.Map.isMap data
				if face?.inspect
					el "div.doll-map",
						toJSList data.map (subData, key)->
							el 'div.doll-entry',
								el 'div.doll-key',
									ui.editable 'div.string-content', key, (e)->
										newKey = e.value
										unless data.has newKey
											mutate name, (data)->
												data.remove key
												.set newKey, subData
											oldName = name.push key
											if (oldAka = namesplace.get oldName)
												rename oldAka, (aka)->aka.remove(oldName).add name.push newKey
										else 
											mutateFace name, (x)->x
								do mapKeyFace =->
									renderFace name.push(key), subData
						el 'button',
							onclick: ->
								mutate name, (data)->
									i = 1
									name = 'new_'
									i += 1 while data.has name+i
									data.set name+i, null
							'+'
				else
					el 'div.doll-map.summary', "#{data.count()} keys"

verbs.identity.__backward = (old, s)->
	@mutate [1], ->s

backward = (name, old, want)->
	forward = root.getIn name
	if isApplication forward
		verb = forward.first()
		if verb.__backward
			console.log 'running back', verb.__backward
			ctx =
				mutate: (n, fn)->
					mutate name.concat(n), fn
			verb.__backward.call ctx, old, want
	mutateFace name, (x)->x
	do renderer
	
							
mutate = (name, mutator)->
	mutations.push {name, mutator}
	if name.contains '__forward'
		i = name.findLastIndex (x)->x is '__forward'
		name = name.take(i)
		data = realize root.getIn name
		newData = mutator.call null, data 
		return backward name, data, newData 

	aka = namesplace.get(name) or Immutable.Set.of name
	data = root.getIn name
	newData = mutator.call null, data 
	aka.forEach (name)->
		root = root.setIn name, newData
		while name.size
			name = name.pop()
			if (aka = namesplace.get(name))?.size > 1
				mutate name, (x)->x
				break
	do renderer
	newData

mutateFace = (name, mutator)->
	face = faces.get(name) or new Face {name}
	mutations.push {face, name, mutator}
	newFace = mutator.call null, face
	domCache.delete face
	unless newFace and (newFace.inspect or newFace.highlight)
		faces = faces.remove name
	else
		faces = faces.set name, newFace
	while name.size
		name = name.pop()
		old = faces.get(name)
		if old
			domCache.delete old
	do renderer

rename = (aka, mutator)->
	newAka = mutator.call null, aka
	left = aka.subtract newAka
	namesplace = namesplace.withMutations (namesplace)->
		left.forEach (name)->
			namesplace = namesplace.set name, left
		newAka.forEach (name)->
			namesplace = namesplace.set name, newAka
		namesplace
	mutate newAka.first(), ((x)->x) if newAka.count()
	mutate left.first(), ((x)->x)  if left.count()
	
unname = (name)->
	aka = namesplace.get name
	if aka
		rename aka, (aka)->aka.remove name
	if name.size
		key = name.last()
		oname = name.pop()
		root = root.updateIn oname, (owner)->
			if Immutable.Iterable.isIndexed(owner) and key < owner.size - 1
				owner.forEach (v, k)->
					return if k < key
					oldName = oname.push(k + 1)
					if (oldAka = namesplace.get oldName)
						rename oldAka, (aka)->aka.remove(oldName).add(oname.push(k))

			owner.remove key
	else root = Immutable.List()
	do renderer

	
update = (tree)->
	unless isVNode tree
		tree = el 'div.json-tree', JSON.stringify tree
	newDom = toVDom tree
	patch = VDom.diff currentDom, newDom
	rootElement = VDom.patch rootElement, patch
	# console.log 'patching dom', newDom, 'patch', patch
	currentDom = newDom

storedFaces = storedNames = null
mutations = []
rendering = no
renderer =(save = yes, buffer = yes)->
	unless rendering
		rendering = yes
		window.requestAnimationFrame ->
			deadline = Date.now() + 50
			console.log 'rendering mutations:', mutations
			mutations = []
			if root isnt rootStack.peek()
				localStorage.setItem 'stored state', serialize root
			if save and root isnt rootStack.peek()
				rootStack = rootStack.push root
			if faces isnt storedFaces
				localStorage.setItem 'stored faces', serializeFaces()
				storedFaces = faces
			if namesplace isnt storedNames
				localStorage.setItem 'stored names', serializeNames()
				storedNames = namesplace
			updater = do (root)->rootRenderer=->
				update layout renderFace Immutable.List(), root
				rendering = no
			if Date.now() > deadline
				do delayedUpdater =->
					window.requestAnimationFrame updater
			else
				do updater


stringifier = (key, fn)->
	if typeof fn is 'function'
		_fn: fn.toString()
		__macro: fn.__macro
	else fn
serialize =(tree)->JSON.stringify tree, stringifier 
serializeNames =-> JSON.stringify namesplace.toObject()
serialCache = new WeakMap
serializeFaces =-> JSON.stringify faces.map((f, k)->[k, {inspect:f.inspect,name:f.name.toArray()}]).toArray()

deserialize = (text)->
	try
		Immutable.fromJS JSON.parse(text), (key, fn)->
			if fn.get '_fn'
				macro = fn.get '__macro'
				eval "fn = #{fn.get '_fn'};"
				if macro
					fn.__macro = yes
				return fn
			else if Immutable.Iterable.isIndexed fn
				fn.toList()
			else
				fn.toMap()
	catch e
		throw e
		console.log "couldn't deserialize", text
		root

do deserializing =->
	if (store = localStorage.getItem('stored state'))
		root = deserialize store
		unless root.hashCode
			root = Immutable.List()
		console.log 'deserialized', store, root?.toJS?() or root

	if (store = localStorage.getItem('stored names'))
		names = (deserialize store)
		.filter (aka)->aka.every (name)->root.hasIn name
		namesplace = namesplace.withMutations (ns)->
			names.forEach (aka, name)->
				aka.forEach (name)->
					ns.set name, aka.toSet()
			ns
		console.log 'deserialized', store, namesplace.toJS()

	if (store = localStorage.getItem('stored faces'))
		faces = Immutable.fromJS _.object JSON.parse(store) 
		.filter (face)->root.hasIn face.get 'name'
		console.log 'faces', faces.toJS()
		faces = faces.flip().map((v, k)->Immutable.fromJS k.get 'name').flip().map (v)-> new Face v
		console.log 'faces',faces.toJS()

do initialRender =->
	initialize dom = layout fd = renderFace Immutable.List(), root 
