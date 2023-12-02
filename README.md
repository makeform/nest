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
