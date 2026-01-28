module.exports =
  pkg:
    extend: {name: "@makeform/common"}
    dependencies: [
      {name: "proxise"}
      {name: "ldview"}
      {name: "@plotdb/form"}
    ]
  init: (opt) ->
    # subinit > init > @widget is created.
    # thus, when subblock fire `init.nest`, widget can be consider prepared
    # we may consider adding `widget.inited` event in @makeform/base
    opt.pubsub.fire \subinit, mod: mod(opt)

mod = ({root, ctx, data, parent, t, i18n, manager, pubsub}) ->
  {ldview, form} = ctx
  obj =
    host: {}
    data:
      list: []  # for list mode
      object: {} # for object mode
    fields: null
    entry: {} # for non-serializable objects associated with entries in data.list by key
    subcond: ({field, key}) -> if !key => [v.subcond for k,v of @entry].filter(->it)

  _adapt = (itf) ->
    if !(itf and itf.adapt) => return
    itf.adapt({} <<< obj.host <<< {
      upload: ({file, progress, alias}) ~>
        obj.host.upload({file, progress, alias: alias or name})
    })

  f = (opt = {}) ~>
    obj <<< opt{fields or {}, conditions, onchange, validate, instance, autofill, adapt, doctree, composing}
    obj.mode = opt.mode or \list
    obj.display = opt.display or \all # active or all
    obj.viewcfg = opt.view or {}
    # obj.init should be available since obj.init will be prepared synchronously in init below.
    Promise.resolve!
      .then -> obj.init!
      .then (ctx) -> if opt.init => opt.init.apply obj._ctx, [obj]

  pubsub.on \@makeform/nest:init, f
  # potential ambigious event name thus we deprecated it. use `@makeform/nest:init` instead
  pubsub.on \init.nest, f

  init: ->
    # we use sig to let `@on 'change'` below know if the event is from internal value update.
    # because we don't need rerender for internal value update
    # so why do we still fire change event? because we need it to notify parent that values are changed.
    # parent nest widget relys on widget's change event to update value, so it's necessary.
    # NOTE thus - we should always regen sig if we update value,
    # otherwise remote value may not be updated correctly.
    # we may consider redesign how `value` works by recursively fetching value from widgets everytime
    # which eliminate the need to update value completely.

    # Approach A: write a random sig token in data.
    # this correctly works for distinguish update source yet it makes data becom dirty easily.
    /*
    sig =
      same: (d) ->
        token = ((obj.data or {}).sig or {}).token
        return token and (d.sig or {}).token == token
      renew: ->
        sig = obj.data.{}sig
        sig <<< count: sig.count or 0, ts: Date.now!
        sig.token = "#{Math.random!toString(36)substring(2)}-#{sig.ts}-#{sig.count}"
    clear: -> # do nothing, since sig token always be replaced when renew.
    */
    # Approach B: simply use a flag.
    # there may be race condition between flag > update
    # yet once a change event will be fired everytime when flag is on
    # we can at least always cancel one flag. e.g.,
    #  default scene : flag on > inner update(block) > flag down
    #  race condition: flag on > outer update(block) > flag down > inner update
    sig =
      same: -> @internal
      renew: -> @internal = true
      clear: -> @internal = false

    # from htc-viveland-2025. however, we need to cache the original readonly value,
    # and take into account the effects of the conditions
    lc =
      meta: {}
      # readonlys[entry key][field name]:
      #   original readonly value for widget <field name> in <entry key>
      readonlys: {}
      # use to store last value of readonly
      # since we still control some edit functions
      # we can use this to decide whether to accept update or not
      # it can be true, false or undefined
      readonly: undefined

    remeta = (meta = {}, o = {}) ->
      lc.meta = JSON.parse(JSON.stringify(meta))
      if lc.readonly == lc.meta.readonly => return
      lc.readonly = !!lc.meta.readonly
      for k,v of obj.entry =>
        for n, f of v.fields =>
          if !(itf = v.block[n].cfg.itf) => continue
          if !(lc.readonlys[k] or {})[n]? => lc.readonlys{}[k][n] = !!f.meta.readonly
          # field should always be readonly if widget is readonly.
          nv = if lc.readonly => lc.readonly else lc.readonlys[k][n]
          m = itf.serialize!
          # don't deserialize if no change to optimize performance.
          if m.readonly == nv => continue
          m.readonly = nv
          itf.deserialize m, o

    @on \meta, (m, o) ~> remeta @serialize!, o
    remeta data

    @on \mode, (m) ~> for k,v of obj.entry => v.formmgr.mode m
    @on \change, (d = {}) ->
      if sig.same(d) => return sig.clear!
      obj.data = d
      if obj.mode == \list =>
        obj.data.[]list
        keyhash = Object.fromEntries obj.data.list.map(->[it.key,true])
        if !obj.active-key => obj.active-key = (obj.data.list.0 or {}).key
        for k,v of obj.entry => if !keyhash[k] => delete obj.entry[k]
        obj.view.render!
        obj.data.list.map (e) ->
          if !obj.entry[e.key] => return
          ps = [v for k,v of obj.entry[e.key].block or {}].map -> it.init!
          Promise.all ps
            .then -> obj.entry[e.key].formmgr.value e.value
            .then -> if obj.onchange => obj.onchange {formmgr: obj.entry[e.key].formmgr}
      else
        # if data of this field were from some other fields, it may not contain data.object.
        # thus we must make sure it exist.
        obj.data.{}object
        key = undefined
        ps = [v for k,v of (obj.entry[key].block or {})].map -> it.init!
        Promise.all ps
          .then -> obj.entry[key].formmgr.value obj.data.object
          .then -> if obj.onchange => obj.onchange {formmgr: obj.entry[key].formmgr}

    _viewcfg = (viewcfg) ~>
      update = ~>
        sig.renew!
        # obj.data{sig} is deprecated. here we still keep it's value. see sig object comments above.
        v = if obj.mode == \list => obj.data{list,sig} else obj.data{object,sig}
        if !v.sig => delete v.sig
        @value v
      action-click =
        add: ->
          if lc.readonly => return
          list = obj.data.list
          list.push {value: {}, key: Math.random!toString(36).substring(2), idx: list.length + 1}
          update!
          obj.view.render!
          # ld-each entry may need i18n translation again if we change language after ldview inited.
          # thus, we will transform everytime after rendering.
          # we may need a better way to handle this.
          if obj.instance and obj.instance.transform => obj.instance.transform \i18n
        delete: ({node, ctx, ctxs}) ->
          if lc.readonly => return
          list = obj.data.list
          list.splice list.indexOf(ctx), 1
          list.map (d,i) -> d.idx = i + 1
          delete obj.entry[ctx.key]
          update!
          obj.view.render!

      block-processor =
        init: ({node, entry, name, bobj, cfg}) ~>
          if !cfg =>
            try
              if !obj.fields[name] or !(cfg = JSON.parse JSON.stringify obj.fields[name]) =>
                throw new Error("config not found for field #{name}")
            catch e
              console.warn "exception when parsing block data for field name `#name`."
              throw e
          if !cfg.meta.title => cfg.meta.title = name
          entry.block[name] =
            cfg: cfg
            path: name
            inited: false
            init: proxise -> if @inited => return Promise.resolve!
          node.classList.toggle \d-none, true
          # ensure the init rendering align with config
          if lc.readonly => cfg.meta.readonly = true
          Promise.resolve!
            .then ~>
              if bobj => return cfg <<< {root: node} <<< bobj{itf, bi}
              bdef = if typeof(cfg.type) == \object => cfg.type
              else if typeof(cfg.type) == \string => {name: cfg.type, version: \main}
              else {name: '@makeform/input', version: \main}
              manager.from bdef, {root: node, data: cfg.meta}
                .then (o) ~>
                  cfg <<< {itf: o.interface, bi: o.instance, root: node}
                  # this is for cond
                  entry.fields[name] <<< {itf: o.interface, bi: o.instance, root: node}
            .then ~>
              # again since remeta may be called before module loaded
              itf = cfg.itf
              if lc.readonly => cfg.meta.readonly = true
              itf.deserialize cfg.meta, {init: true}
              _adapt itf
              entry.formmgr.add {widget: itf, path: name}
              itf.mode entry.formmgr.mode!
              entry.block[name].inited = true
              entry.block[name].init.resolve true
              if itf.manager!length => @fire \manager.changed
              itf.on \manager.changed, ~> @fire \manager.changed
              itf.on \meta, ~> @fire \meta, @serialize!
              if !(itf.ctrl and (ret = itf.ctrl!) and ret.condctrl) => return
              entry.subcond = ret.condctrl
            .catch (e) -> return Promise.reject(e)
        handler: ({node, name, ctx}) ->
          cfg = (((obj.entry[ctx.key] or {}).block or {})[name] or {}).cfg or {}
          vis = (((obj.entry[ctx.key] or {}).cond or {})._visibility or {})[name]
          node.classList.toggle \d-none, (vis? and !vis)
          # we should render subblock when this block is rendered.
          # however, when there are many widgets,
          # this might lead to significant performance issue.
          # the main reason is because for now every value change leads to a rerendering
          # of the whole form.
          # we will have to refactor the whole form design about rendering to improve this.
          if !cfg.itf => return
          # TODO this seems to not work since once we render more than once,
          # widget still be rendered. consider remove this.
          if (dirty = obj.entry[ctx.key].dirty) and dirty.size =>
            if dirty.has name => dirty.delete name
            return
          if cfg.lng != i18n.language =>
            cfg.bi.transform \i18n
            cfg.lng = i18n.language
            # we suppose widget should render themselves for meta/value update,
            # thus re-render is not necessary everytime;
            # so we move it inside language transform block.
            cfg.itf.render!

      handler =
        add: ({node, ctx}) ~> node.style.display = if (@mode! == \view or lc.readonly) => \none else ''
        "no-entry": ({node}) ~> node.classList.toggle \d-none, @content!length
        entry:
          init:
            "@": ({ctx, node, views}) ~>
              init = (ret = {}) ~>
                obj.docroot = ret.host
                # cond use itf from fields. yet obj.fields is shared. so we dup it here.
                # ctx.key for object mode will be undefined.
                obj.entry[ctx.key] =
                  fields: {}
                  doctree: blocks
                  block: {}
                  formmgr: fmgr = new form.manager!
                  cond: new condctrl base-rule: ({meta}) -> if lc.readonly => meta.readonly = true
                # FMGR/COND this is a experimental implementation of condition directly in formmgr,
                # which attempt to support condition directly in formmgr.
                # before we finalize the implementation, keep the sample code here for reference.
                # see also FMGR/COND below
                # fmgr.condition!reset conditions: /* TBD, such as obj.cx */
                if obj.docroot =>
                  blocks = obj.docroot.nodemgr!blocks!
                  entry = obj.entry[ctx.key]
                  for b in blocks =>
                    name = b.node.id
                    dom = obj.docroot.nodemgr!get-dom {id: name}
                    meta = b.block.interface.serialize!
                    block-processor.init {
                      entry, name, cfg: {meta}
                      node: dom
                      bobj: {itf: b.block.interface, bi: b.block.instance}
                    }
                else for k,v of obj.fields => obj.entry[ctx.key].fields[k] = {} <<< v
                obj.entry[ctx.key].cond.init {
                  fields: obj.entry[ctx.key].fields
                  conditions: obj.conditions or []
                }
                fmgr.mode @mode!
                debounce 350 .then ->
                  # prevent exception caused by quick deletion
                  if !obj.entry[ctx.key] => return
                  obj.entry[ctx.key].cond.run!
                  # fmgr.condition!run! # see FMGR/COND above
                  views.0.render!
                fmgr.on \change, (info) ->
                  if !obj.entry[ctx.key] => return
                  obj.entry[ctx.key].cond.run!
                  # fmgr.condition!run! # see FMGR/COND above
                  # dirty: record changed paths to ensure minimal rendering.
                  # when render with dirty items: only render those in dirty set.
                  # otherwise render everything.
                  if !obj.entry[ctx.key].dirty => obj.entry[ctx.key].dirty = new Set!
                  if info and info.path => obj.entry[ctx.key].dirty.add info.path
                  views.0.render!
                  if obj.mode == \list =>
                    # ctx may not be the original object, because it may be updated
                    # and this is init which will only be called once.
                    # thus we get the data object directly from obj.data.list
                    if !(ret = obj.data.list.filter(-> it.key == ctx.key).0) => return
                    ret.value = JSON.parse(JSON.stringify(fmgr.value!))
                  else
                    obj.data.object = JSON.parse(JSON.stringify(fmgr.value!)) or {}
                  update!
                @fire \manager.changed
                if obj.instance and obj.instance.transform => obj.instance.transform \i18n

              # composing: focus on nodetree editing and don't render entry
              if !(obj.doctree and !obj.composing) => init!
              else obj.doctree {root: node.querySelector('[ld=docroot]') or node} .then init

            block: ({node, ctxs, ctx}) ~>
              entry = obj.entry[ctx.key]
              name = node.dataset.name
              block-processor.init {node, entry, name}

          handler:
            delete: ({node, ctx}) ~> node.style.display = if (@mode! == \view or lc.readonly) => \none else ''
            "@": ({node, ctx}) ~>
              if obj.display == \active =>
                node.classList.toggle \d-none, (ctx.key != obj.active-key)
              if !obj.doctree or obj.composing => return
              if !((docroot = obj.docroot) and docroot.nodemgr) => return
              blocks = if docroot => docroot.nodemgr!blocks! else null
              entry = obj.entry[ctx.key]
              for b in blocks =>
                name = b.node.id
                dom = docroot.nodemgr!get-dom {id: name}
                block-processor.handler {node: dom, name, ctx}

            lng: ({node}) ~>
              node.classList.toggle \d-none, !(
                i18n.language.startsWith(node.dataset.lng) or
                i18n.language.startsWith("#{node.dataset.lng}-")
              )
            visibility: ({node, ctx}) ~>
              name = node.getAttribute \data-name
              node.classList.toggle \d-none, false
              vis = (((obj.entry[ctx.key] or {}).cond or {})._visibility or {})[name]
              node.classList.toggle \d-none, (vis? and !vis)
            autofill: ({node, views, ctx}) ~>
              name = node.dataset.name
              cfg = (((obj.entry[ctx.key] or {}).block or {})[name] or {}).cfg or {}
              if cfg and cfg.itf =>
                if !cfg.autofill => cfg.itf.on \change, (cfg.autofill = -> views.0.render \autofill)
                node.textContent = cfg.itf.content!
              else if @autofill? => node.textContent = @autofill {name}

            block: ({node, ctxs, ctx}) ~>
              name = node.getAttribute(\data-name)
              block-processor.handler {node, name, ctx}

      opt = {} <<< (viewcfg.common or {}) <<< {
        init-render: false
        root: root
        # this may lead to name collision of `key` and fields named `key` in object mode.
        # since only `ctx.key` is used above we may consider using `{}` instead.
        ctx: -> obj.data.object or {}
      }

      # for list mode
      if obj.mode == \list =>
        opt.{}action.{}click.add = action-click.add
        opt.{}handler["no-entry"] = handler["no-entry"]
        opt.{}handler.add = handler.add
        opt.{}handler.entry =
          list: -> obj.data.list or []
          key: -> it.key
          view: {} <<< (viewcfg.entry or {})
        opt.handler.entry.view
          ..{}action.{}click.delete = action-click.delete
          ..{}init <<< handler.entry.init
          ..{}handler <<< handler.entry.handler
      else
        # for object mode
        opt.{}init <<< handler.entry.init
        opt.{}handler <<< handler.entry.handler
      return opt

    obj.init = proxise.once ~>
      if obj.inited => return
      obj._ctx = @
      obj.inited = true
      if !obj.fields => return
      obj.view = new ldview _viewcfg obj.viewcfg
      <~ obj.view.init!then _
      i18n.on \languageChanged, -> obj.view.render \lng
      obj.view.render!
      return @

    obj.init!

  render: -> if obj.view => obj.view.render!
  is-equal: (a,b) -> JSON.stringify(a) == JSON.stringify(b)
  is-empty: (a) ->
    if obj.mode == \list => return !a or JSON.stringify(a) == "{}" or !a.list or !a.list.length
    return !a or JSON.stringify(a) == "{}"
  content: ->
    if obj.mode == \list => obj.data.list # for term validation to work.
    else obj.data.object
  validate: (opt = {}) ->
    ps = [v for k,v of obj.entry or {}]
      .map (o) ->
        Promise.all([v for k,v of o.block].map -> v.init!)
          .then (r) ->
            is-init = r.filter(->it).length or opt.init
            ws = [v for k,v of o.block]
              .filter -> !it.cfg.itf.disabled!
            check-ws = ws
              .filter ->
                it.cfg.itf and
                (
                  !it.cfg.itf.is-empty! or
                  # consider not-required empty fields as mandatory to check
                  # thus it won't prevent base widget from being considered finished
                  (it.cfg.itf.is-empty! and !it.cfg.itf.is-required!) or
                  it.cfg.itf.status! == 2
                ) and
                !it.cfg.itf.disabled!
              .map -> {widget: it.cfg.itf, path: it.path}
            if !check-ws.length and !opt.force =>
              o.status = 1
              return o
            check-ws = if opt.force => null else check-ws
            o.formmgr.check check-ws, {now: true, init: is-init, force: opt.force}
              .then (r) ->
                o.status = if r.length => 2
                else if is-init or (check-ws and check-ws.length < ws.length) => 1
                else if (check-ws or []).filter(->it.widget.status! == 3).length => 3
                else 0
                return o
    Promise.all ps
      .then (rs) ~>
        count = [0,0,0,0]
        rs.forEach (o) -> count[o.status]++
        if count.2 => return ["nested"]
        Promise.resolve!
          .then ->
            if !obj.validate => return
            obj.validate opt, obj
          .then (ret) ->
            if ret => return that
            # some fields are not touched or editing, thus this widget is editing
            if count.1 or count.3 => return {status: 3, errors: []}
            return []

  adapt: (host) ->
    obj.host = host
    if obj.adapt => obj.adapt host
    for key,entry of obj.entry => for name, field of entry.fields => if field.itf => _adapt field.itf

  manager: ({depth = 0} = {}) ->
    ret = [v for k,v of obj.entry or {}].map(->it.formmgr).filter(->it)
    if depth == 1 => return ret
    for k,v of obj.entry => for g,u of v.block =>
      if u.cfg.itf and (mgrs = u.cfg.itf.manager({depth: depth - 1})).length => ret ++= mgrs
    return ret
  ctrl: ->
    toggle: (o = {}) ~>
      if o.key => obj.active-key = o.key
      obj.view.render!
    condctrl: -> return Object.fromEntries [[k,v.cond] for k,v of obj.entry]
