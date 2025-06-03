condctrl = (opt = {}) ->
  @ <<< _hash: {}, _visibility: {}, _fields: (opt.fields or {}), list: opt.conditions or []
  @

condctrl.prototype = Object.create(Object.prototype) <<<
  # we now consider visible as enabled. this may be separated in the future, if necessary.
  is-visible: -> @_visibility[it]
  is-enabled: -> @_visibility[it]
  get: (id) -> @_hash[id]
  subcond: ({target, config, active}) ->
    itf = @_fields[target].itf
    if !(itf and itf.ctrl and (ret = itf.ctrl!) and (conds = ret.condctrl!)) => return
    for k, cond of conds =>
      cond.apply {active} <<< config
      # cond is changed, which may trigger a chain reaction, so we should rerun cond.run.
      # TODO we may want to batch this call since it may be run multiple times.
      cond.run!
  init: (opt = {}) ->
    @_fields = opt.fields or @_fields or {}
    for k,v of @_fields =>
      if !(v.meta or {}).condition => continue
      @list.splice 0, 0, {src: k, config: v.meta.condition}
    for i from 0 til @list.length =>
      cond = @list[i]
      if !cond.id => cond.id = "#{(i + 1)}"
      @_hash[cond.id] = cond
      if !Array.isArray(cond.config) => cond.config = [cond.config]
      cond.config.map (cfg) ~>
        # we used to toggle `is-required` along with `enabled`,
        # yet this isn't a best practice and is error-prone due to negligence.
        # thus, we decide to remove this before `@makeform/nest` is widely adopted.
        #is-required = if cfg.is-required? and !cfg.is-required => false else true
        #if cfg.enabled => cfg <<< {disabled: false, is-required}
        #else if cfg.enabled? => cfg <<< {disabled: true, is-required: !is-required}
        if cfg.enabled => cfg <<< {disabled: false}
        else if cfg.enabled? => cfg <<< {disabled: true}
        cfg.source = cond.src
        cfg.func = cond.func
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
    {target, active, enabled, disabled, is-required, readonly} = opt
    if disabled? => @_visibility[target] = !!(disabled xor active)
    if (@_fields[target] and (widget = @_fields[target].itf)) =>
      cur-meta = widget.serialize!
      new-meta = JSON.parse(JSON.stringify(cur-meta))
      if disabled? => new-meta.disabled = !(disabled xor active)
      if readonly? => new-meta.readonly = !(readonly xor active)
      if is-required? => new-meta.is-required = !(is-required xor active)
      if !!cur-meta.disabled == !!new-meta.disabled and
         !!cur-meta.is-required == !!new-meta.is-required and
         !!cur-meta.readonly == !!new-meta.readonly => return
      widget.deserialize new-meta, {init: true}
    if !(Array.isArray(target) and target.1) => return
    @subcond {
      target: target.0
      config: {target: config.target.slice(1), enabled, disabled, is-required, readonly},
      active: active
    }

  # targets is required/visible(based on `is-required` and `visible` field) only if name = val
  _run: (cfg = {}, precond) ->
    {source, values, targets, is-required, enabled, disabled, readonly, func} = cfg
    if func =>
      result = true
      for tgt in targets =>
        active = !!(func.apply @, [{} <<< cfg <<< {target: tgt}]) and !(precond? and !precond)
        result = result and active
        if Array.isArray(tgt) and tgt.1 =>
          @subcond {target: tgt.0, config: {} <<< cfg <<< {target: tgt.slice(1)}, active}
          continue
        @apply {target: tgt, enabled, active, disabled, is-required, readonly}
    else
      if !(@_fields[source] and itf = @_fields[source].itf) =>
        console.error "[nest/condctrl] try to execute a condition with nonexisted fields '#source'"
        return
      content = itf.content!
      content = if Array.isArray(content) => content else [content]
      active = !!content.filter((c) -> if Array.isArray(values) => (c in values) else (c == values)).length
      if precond? and !precond => active = false
      for tgt in targets =>
        if Array.isArray(tgt) and tgt.1 =>
          @subcond {target: tgt.0, config: {} <<< cfg <<< {target: tgt.slice(1)}, active}
          continue
        @apply {target: tgt, enabled, active, disabled, is-required, readonly}
      result = active
    return result

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
