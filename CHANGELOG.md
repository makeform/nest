# Change Logs

## v0.3.5

 - fix bug: meta fallback to `{}` in `remeta`, if not provided
 - upgrade dependency


## v0.3.4

 - fix bug: parent readonly attribute didn't correctly reflect in child widets
 - fix bug: user can still add / remove should not be able to readonly
 - ensure pareny readonly attribute works even with child conditions
 - tweak condctrl code naming and api interface
 - add `baseRule` option in condctrl for overwriting conditions
 - add document about condctrl


## v0.3.3

 - fix bug: exception when condctrl is used along with widgets without meta.


## v0.3.2

 - optimize recursive rendering by bookkeeping a dirty list


## v0.3.1

 - add `fill` mixin in `mixin.pug` for auto filling content


## v0.3.0

 - `is-required` now won't be affected by `enabled` flag
 - propagate readonly into sub-fields
 - hide `add` and `delete` buttons in view mode from code


## v0.2.9

 - fix bug: validate doesn't correctly reflect status 3 from child widgets


## v0.2.8

 - fix bug: ensure obj.data.object availability


## v0.2.7

 - refactor `init.nest` function
 - support `adapt` api


## v0.2.6

 - add `autofill` ld selector
 - call child init with internal `obj` in widget context.


## v0.2.5

 - add `lng` Pug mixin support
 - add `isVisible` and `isEnabled` in cond api
 - add `subcond` api for recursively run condition controller
 - add `active` api to directly


## v0.2.4

 - fix bug: `fromSource` causes parent nest unsync with its widgets. replace `fromSource` with `sig` mechanism.


## v0.2.3

 - update widget value with `fromSource` flag to prevent massive update with any editing.


## v0.2.2

 - fix bug: ensure interface existence before calling adapt


## v0.2.1

 - fix bug: adapt api doesn't recursively call widget's adapt api


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

