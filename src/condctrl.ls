condctrl = (opt = {}) ->
  @ <<< _hash: {}, _visibility: {}, _fields: (opt.fields or {}), list: opt.conditions or []
  @

condctrl.prototype = Object.create(Object.prototype) <<<
  get: (id) -> @_hash[id]
  init: (opt = {}) ->
    @_fields = opt.fields or @_fields or {}
    for k,v of @_fields =>
      if !v.meta.condition => continue
      @list.splice 0, 0, {src: k, config: v.meta.condition}
    for i from 0 til @list.length =>
      cond = @list[i]
      if !cond.id => cond.id = "#{(i + 1)}"
      @_hash[cond.id] = cond
      if !Array.isArray(cond.config) => cond.config = [cond.config]
      cond.config.map (cfg) ~>
        is-required = if cfg.is-required? and !cfg.is-required => false else true
        if cfg.enabled => cfg <<< {disabled: false, is-required}
        else if cfg.enabled? => cfg <<< {disabled: true, is-required: !is-required}
        cfg.source = cond.src
        cfg.targets = Array.from(new Set(
          (if cfg.prefix => cfg.prefix else []) ++
          (cfg.targets or []) ++
          [{k,v} for k,v of @_fields].filter(({k,v}) ->
            return (
              (if !cfg.prefix => 0 else (cfg.prefix.filter((p) -> k.startsWith p).length)) +
              (v.meta.tag or []).filter((t) -> t in (cfg.tags or [])).length
            ) > 0
          ).map(->it.k)
        ))

  apply: (opt = {}) ->
    {widget, active, disabled, is-required, readonly} = opt
    cur-meta = widget.serialize!
    new-meta = JSON.parse(JSON.stringify(cur-meta))
    if disabled? => new-meta.disabled = !(disabled xor active)
    if readonly? => new-meta.readonly = !(readonly xor active)
    if is-required? => new-meta.is-required = !(is-required xor active)
    if !!cur-meta.disabled == !!new-meta.disabled and
       !!cur-meta.is-required == !!new-meta.is-required and
       !!cur-meta.readonly == !!new-meta.readonly => return
    widget.deserialize new-meta, {init: true}

  # targets is required/visible(based on `is-required` and `visible` field) only if name = val
  _run: ({source, values, targets, is-required, disabled, readonly}, precond) ->
    if !(@_fields[source] and itf = @_fields[source].itf) =>
      console.error "[nest/condctrl] try to execute a condition with nonexisted fields '#source'"
      return
    content = itf.content!
    content = if Array.isArray(content) => content else [content]
    active = !!content.filter((c) -> if Array.isArray(values) => (c in values) else (c == values)).length
    if precond? and !precond => active = false
    for tgt in targets =>
      if disabled? => @_visibility[tgt] = !!(disabled xor active)
      if !(@_fields[tgt] and (widget = @_fields[tgt].itf)) => continue
      @apply {widget, active, disabled, is-required, readonly}
    return active

  run: ->
    result = {}
    _ = ~>
      if !arguments.length => list = @list
      else list = Array.from(arguments)
      for i from 0 til list.length =>
        cond = list[i]
        if result[cond.id]? => continue
        if cond.precond and @_hash[cond.precond] => _ @_hash[cond.precond]
        for cfg in cond.config => result[cond.id] = @_run cfg, result[cond.precond]
    _!
