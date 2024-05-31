module.exports =
  pkg:
    extend: {name: "@makeform/common"}
    dependencies: [
      {name: "ldview"}
      {name: "@plotdb/form"}
    ]
  init: (opt) -> opt.pubsub.fire \subinit, mod: mod(opt)

mod = ({root, ctx, data, parent, t, manager, pubsub}) ->
  {ldview, form} = ctx
  obj =
    data:
      list: []  # for list mode
      object: {} # for object mode
    fields: null
    entry: {} # for non-serializable objects associated with entries in data.list by key

  pubsub.on \init.nest, ({mode, fields, view, onchange, validate, instance}) ->
    obj.mode = mode or \list
    obj.fields = fields
    obj.viewcfg = view
    obj.onchange = onchange
    obj.validate = validate
    obj.instance = instance
    if obj.init => obj.init!

  init: ->
    @on \mode, (m) ~> for k,v of obj.entry => v.formmgr.mode m
    @on \change, (d = {}) ->
      obj.data = d or {} 
      if obj.mode == \list =>
        obj.data.[]list
        keys = obj.data.list.map -> it.key
        for k,v of obj.entry => if !(k in keys) => delete obj.entry[k]
        obj.view.render!
        obj.data.list.map (e) ->
          if !obj.entry[e.key] => return
          ps = [v for k,v of obj.entry[e.key].block or {}].map -> it.init!
          Promise.all ps
            .then -> obj.entry[e.key].formmgr.value e.value
            .then -> if obj.onchange => obj.onchange {formmgr: obj.entry[e.key].formmgr}
      else
        key = undefined
        ps = [v for k,v of (obj.entry[key].block or {})].map -> it.init!
        Promise.all ps
          .then -> obj.entry[key].formmgr.value obj.data.object
          .then -> if obj.onchange => obj.onchange {formmgr: obj.entry[key].formmgr}

    _viewcfg = (viewcfg) ~>
      update = ~> @value(if obj.mode == \list => obj.data{list} else obj.data{object})
      handler =
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
        "no-entry": ({node}) ~> node.classList.toggle \d-none, @content!length
        entry:
          init:
            "@": ({ctx}) ~>
              obj.entry[ctx.key] = {block: {}, formmgr: fmgr = new form.manager!}
              fmgr.mode @mode!
              fmgr.on \change, ->
                if obj.mode == \list =>
                  # ctx may not be the original object, because it may be updated
                  # and this is init which will only be called once.
                  # thus we get the data object directly from obj.data.list
                  if !(ret = obj.data.list.filter(-> it.key == ctx.key).0) => return
                  ret.value = JSON.parse(JSON.stringify(fmgr.value!))

                else
                  obj.data.object = JSON.parse(JSON.stringify(fmgr.value!))
                update!
            block: ({node, ctxs, ctx}) ~>
              entry = obj.entry[ctx.key]
              name = node.getAttribute(\data-name)
              if !(cfg = JSON.parse JSON.stringify obj.fields[name]) =>
                return console.warn "config not found for field #{name}"
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
                  o.interface.adapt({} <<< obj.host <<< {
                    upload: ({file, progress, alias}) ~>
                      obj.host.upload({file, progress, alias: alias or name})
                  })
                  entry.formmgr.add {widget: cfg.itf, path: name}
                  cfg.itf.mode entry.formmgr.mode!
                  entry.block[name].inited = true
                  entry.block[name].init.resolve true
                .catch (e) -> return Promise.reject(e)
          handler:
            block: ({node, ctxs, ctx}) ~>
              name = node.getAttribute(\data-name)
              cfg = (((obj.entry[ctx.key] or {}).block or {})[name] or {}).cfg or {}
              node.classList.toggle \d-none, false
              if !cfg.itf => return
              cfg.bi.transform \i18n
              cfg.itf.render!

      opt = {} <<< (viewcfg.common or {}) <<< {
        init-render: false
        root: root
        ctx: -> obj.data.object
      }

      # for list mode
      if obj.mode == \list =>
        opt.{}action.{}click.add = handler.add
        opt.{}handler["no-entry"] = handler["no-entry"]
        opt.{}handler.entry =
          list: -> obj.data.list or []
          key: -> it.key
          view: {} <<< (viewcfg.entry or {})
        opt.handler.entry.view
          ..{}action.{}click.delete = handler.delete
          ..{}init <<< handler.entry.init
          ..{}handler <<< handler.entry.handler
      else
        # for object mode
        opt.{}init <<< handler.entry.init
        opt.{}handler <<< handler.entry.handler
      return opt

    obj.init = ~>
      if !obj.fields => return
      obj.view = new ldview _viewcfg obj.viewcfg
      obj.view.render!

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
                it.cfg.itf and (!it.cfg.itf.is-empty! or it.cfg.itf.status! == 2)
              .map -> {widget: it.cfg.itf, path: it.path}
            if !check-ws.length and !opt.force =>
              o.status = 1
              return o
            check-ws = if opt.force => null else check-ws
            o.formmgr.check check-ws, {now: true, init: is-init}
              .then (r) ->
                o.status = if r.length => 2
                else if is-init or (check-ws and check-ws.length < ws.length) => 1
                else 0
                return o
    Promise.all ps
      .then (rs) ~>
        count = [0,0,0]
        rs.forEach (o) -> count[o.status]++
        if count.2 => return ["nested"]
        Promise.resolve!
          .then ->
            if !obj.validate => return
            obj.validate opt, obj
          .then (ret) ->
            if ret => return that
            # some fields are not touched. thus, this widget is editing
            if count.1 => return {status: 3, errors: []}
            return []

  adapt: -> obj.host = it
  manager: -> [v for k,v of obj.entry or {}].map(->it.formmgr).filter(->it)
