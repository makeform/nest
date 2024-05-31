# @makeform/nest

a nested widget without UI meant to be extend by the actual widget designed by user.

init with pubsub event `init.nest` with following fields:

 - `mode`: either `list` or `object`. default `list`.
 - `view`: object with following fields for different purpose view cfg object:
   - `common`: viewcfg for the whole widget
   - `entry`: viewcfg for each entry
 - `fields`: object containing fields of makeform definition. a sample fields object:

    {
      name: {type: "@makeform/input", meta: {isRequired: true}},
      desc: {type: "@makeform/textarea", meta: {isRequired: false, title: "description"}},
    }
 - `onchange(o)`: called when there are changes from formmgr. `o` is an object with following fields:
   - `formmgr`: the formmgr from which the change event fires.
 - `validate(opt,obj)`: customized validation function.
   - `opt`: options including `init`, `force`. see `@plotdb/form` for more information.
   - `obj`: additional object from nest widget. contains following fields:
     - `entry`: a hash for all entries. containing `formmgr` field for manipulation.
       - WIP this is only tested against list mode.
   - it should return either null (for no error), or:
     - a list of error messages.
     - an object with `status` field (0 ~ 3) and `errors` fields (a list of error messages)
 - `instance`: the block instance of your block. optional.
   - while `@makeform/nest` renders things for you, it doesn't have your instance object and thus
     it can't call your transform for i18n if needed. If you need post-i18n during view rendering,
     put your instance object (usually available in `@_instance`) here.


## Usage

Create your own block and extend this widget:

    div
      div(plug="widget"): //- your DOM here
      script(type="@plotdb/block"):lsc
        obj = { /* your options here */ };
        module.exports = {
          pkg: {extend: {name: "@makeform/nest", dom: "overwrite"}}
          init: ({pubsub, parent, i18n}) ->
            pubsub.fire("init.nest", obj)
        }

Where `obj` fired along with the `init.nest` event to `@makeform/nest` via `pubsub` is described as above.

Note that you should overwrite `@makeform/nest`'s DOM and implement `widget` plug manually for ancestor `@makeform/common`.
