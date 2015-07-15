_ = require 'lodash'
h = require 'virtual-dom/virtual-hyperscript'
h.svg = require 'virtual-dom/virtual-hyperscript/svg'
VNode = require 'virtual-dom/vnode/vnode'
VText = require 'virtual-dom/vnode/vtext'
isWidget = require 'virtual-dom/vnode/is-widget'
VThunk = require 'vdom-thunk'

module.exports = el = (tag, props, children...)->
	if tag is null
		children.unshift props
		return children
	if props instanceof VNode or isWidget(props) or Array.isArray props
		children.unshift props
		props = null
	else if typeof props is 'string'
		children.unshift new VText props
		props = null
	if children.length is 0
		children = null
	
	unless typeof tag is 'string' and tag.match /^\w/
		throw new Error "#{tag} is not a valid el tag"
	props = _.cloneDeep props
	h tag, props, children

el.svg = (tag, props, children...)->
	if props instanceof VNode
		children.unshift props
		props = null
	else if typeof props is 'string'
		children.unshift new VText props
		props = null
	if children.length is 0
		children = null
	h.svg tag, props, children
	
el.cache = (id, keys..., fn)->
	thunk = VThunk fn, keys...
	thunk.key = id
	thunk
