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

