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

  pubsub.on \init.nest, (opt = {}) ~>
    obj <<< opt{fields, conditions, onchange, validate, instance, autofill, adapt}
    obj.mode = opt.mode or \list
    obj.display = opt.display or \all # active or all
    obj.viewcfg = opt.view or {}
    # obj.init should be available since obj.init will be prepared synchronously in init below.
    Promise.resolve!
      .then -> obj.init!
      .then (ctx) -> if opt.init => opt.init.apply obj._ctx, [obj]

  init: ->
    # we use sig to let `@on 'change'` below know if the event is from internal value update.
    # because we don't need rerender for internal value update
    # so why do we still fire change event? because we need it to notify parent that values are changed.
    # parent nest widget relys on widget's change event to update value, so it's necessary.
    # NOTE thus - we should always regen sig if we update value,
    # otherwise remote value may not be updated correctly.
    # we may consider redesign how `value` works by recursively fetching value from widgets everytime
    # which eliminate the need to update value completely.
    same-sig = (d) ->
      token = ((obj.data or {}).sig or {}).token
      return token and (d.sig or {}).token == token
    resig = ->
      sig = obj.data.{}sig
      sig <<< count: sig.count or 0, ts: Date.now!
      sig.token = "#{Math.random!toString(36)substring(2)}-#{sig.ts}-#{sig.count}"

    # from htc-viveland-2025. however, we need to cache the original readonly value,
    # and take into account the effects of the conditions
    lc = meta: {}, readonlys: {}, readonly: undefined
    remeta = (meta) ->
      lc.meta = meta
      if lc.readonly == !!lc.meta.readonly => return
      lc.readonly = !!lc.meta.readonly
      for k,v of obj.entry =>
        for n, f of v.fields =>
          if !(lc.readonlys[k] or {})[n]? => lc.readonlys{}[k][n] = !!f.meta.readonly
          f.meta.readonly = if lc.meta.readonly => lc.meta.readonly else lc.readonlys[k][n]
          if f.itf => f.itf.deserialize f.meta

    @on \meta, (m) ~> remeta @serialize!
    remeta data

    @on \mode, (m) ~> for k,v of obj.entry => v.formmgr.mode m
    @on \change, (d = {}) ->
      if same-sig(d) => return
      obj.data = d
      if obj.mode == \list =>
        obj.data.[]list
        keys = obj.data.list.map -> it.key
        if !obj.active-key => obj.active-key = keys.0
        for k,v of obj.entry => if !(k in keys) => delete obj.entry[k]
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
        # be sure to call `resig` for every @value update
        resig!
        @value((if obj.mode == \list => obj.data{list,sig} else obj.data{object,sig}))
      action-click =
        add: ->
          list = obj.data.list
          list.push {value: {}, key: Math.random!toString(36).substring(2), idx: list.length + 1}
          update!
          obj.view.render!
          # ld-each entry may need i18n translation again if we change language after ldview inited.
          # thus, we will transform everytime after rendering.
          # we may need a better way to handle this.
          if obj.instance and obj.instance.transform => obj.instance.transform \i18n
        delete: ({node, ctx, ctxs}) ->
          list = obj.data.list
          list.splice list.indexOf(ctx), 1
          list.map (d,i) -> d.idx = i + 1
          delete obj.entry[ctx.key]
          update!
          obj.view.render!
      handler =
        add: ({node, ctx}) ~> node.style.display = if (@mode! == \view) => \none else ''
        "no-entry": ({node}) ~> node.classList.toggle \d-none, @content!length
        entry:
          init:
            "@": ({ctx, views}) ~>
              # cond use itf from fields. yet obj.fields is shared. so we dup it here.
              # ctx.key for object mode will be undefined.
              obj.entry[ctx.key] =
                fields: {}
                block: {}
                formmgr: fmgr = new form.manager!
                cond: new condctrl!
              for k,v of obj.fields => obj.entry[ctx.key].fields[k] = {} <<< v

              obj.entry[ctx.key].cond.list = (obj.conditions or [])
              obj.entry[ctx.key].cond.init {fields: obj.entry[ctx.key].fields}
              fmgr.mode @mode!
              debounce 350 .then ->
                # prevent exception caused byquick deletion
                if !obj.entry[ctx.key] => return
                obj.entry[ctx.key].cond.run!
                views.0.render!
              fmgr.on \change, ->
                if !obj.entry[ctx.key] => return
                obj.entry[ctx.key].cond.run!
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
            block: ({node, ctxs, ctx}) ~>
              entry = obj.entry[ctx.key]
              name = node.dataset.name
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
              bdef = if typeof(cfg.type) == \object => cfg.type
              else if typeof(cfg.type) == \string => {name: cfg.type, version: \main}
              else {name: '@makeform/input', version: \main}
              manager.from bdef, {root: node, data: cfg.meta}
                .then (o) ~>
                  cfg <<< {itf: o.interface, bi: o.instance, root: node}
                  # this is for cond
                  entry.fields[name] <<< {itf: o.interface, bi: o.instance, root: node}
                  _adapt o.interface
                  entry.formmgr.add {widget: cfg.itf, path: name}
                  cfg.itf.mode entry.formmgr.mode!
                  entry.block[name].inited = true
                  entry.block[name].init.resolve true
                  if o.interface.manager!length => @fire \manager.changed
                  o.interface.on \manager.changed, ~> @fire \manager.changed
                  if !(o.interface.ctrl and (ret = o.interface.ctrl!) and ret.condctrl) => return
                  entry.subcond = ret.condctrl
                .catch (e) -> return Promise.reject(e)
          handler:
            delete: ({node, ctx}) ~> node.style.display = if (@mode! == \view) => \none else ''
            "@": ({node, ctx}) ~>
              if obj.display != \active => return
              node.classList.toggle \d-none, (ctx.key != obj.active-key)

            lng: ({node}) ~>
              node.classList.toggle \d-none, !(
                i18n.language.startsWith(node.dataset.lng) or
                i18n.language.startsWith("#{node.dataset.lng}-")
              )
            visibility: ({node, ctx}) ~>
              name = node.getAttribute \data-name
              node.classList.toggle \d-none, false
              vis = (obj.entry[ctx.key] or {}).cond._visibility[name]
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
              cfg = (((obj.entry[ctx.key] or {}).block or {})[name] or {}).cfg or {}
              node.classList.toggle \d-none, false
              vis = (obj.entry[ctx.key] or {}).cond._visibility[name]

              node.classList.toggle \d-none, (vis? and !vis)
              # we should render subblock when this block is rendered.
              # however, when there are many widgets,
              # this might lead to significant performance issue.
              # the main reason is because for now every value change leads to a rerendering
              # of the whole form.
              # we will have to refactor the whole form design about rendering to improve this.
              if !cfg.itf => return
              cfg.bi.transform \i18n
              cfg.itf.render!

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
            check-ws = ws
              .filter ->
                it.cfg.itf and (!it.cfg.itf.is-empty! or it.cfg.itf.status! == 2) and !it.cfg.itf.disabled!
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

  manager: (cb) ->
    ret = [v for k,v of obj.entry or {}].map(->it.formmgr).filter(->it)
    for k,v of obj.entry => for g,u of v.block =>
      if u.cfg.itf and (mgrs = u.cfg.itf.manager!).length => ret ++= mgrs
    ret
  ctrl: ->
    toggle: (o = {}) ~>
      if o.key => obj.active-key = o.key
      obj.view.render!
    condctrl: -> return Object.fromEntries [[k,v.cond] for k,v of obj.entry]
