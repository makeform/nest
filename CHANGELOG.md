# Change Logs

## v0.2.0

 - support `lng` ld selector for togglging block based on lng. requires `@plotdb/block` > v5.5.3


## v0.1.2

 - fix bug: i18n doesn't work. fields transforming and rendering are still required


## v0.1.1

 - fix bug: check `obj.entry[ctx.key]` in debounce function to prevent exception caused by race condition


## v0.1.0

 - proper document init order
 - add `display` option to support toggling active item
 - fallback viewcfg to {} to prevent exception and simplify api
 - add `condctrl` and condition support
 - support additional init function
 - support `manager.changed` event for deep nested widgets
 - check field availability before accessing and always fire exception
 - directly support visibility control
 - provide acommpanying mixin including `widget` and `vis` mixins in pug.
 - recursive validation check only fields that are not disabled
 - pass `force` option into recursive validation


## v0.0.6

 - support `instance` option for i18n


## v0.0.5

 - support custom validation function


## v0.0.4

 - support `onchange` parameter for extending nest with custom actions when there are changes.


## v0.0.3

 - fix bug: `empty` should be checked based on mode


## v0.0.2

 - use `nested` instead of `error` to indicate a nested error.


## v0.0.1

 - init release

