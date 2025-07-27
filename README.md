# @makeform/nest

a nested widget without UI meant to be extend by the actual widget designed by user.

init with pubsub event `@makeform/nest:init` (or deprecated `init.nest` event) with following fields:

 - `init(obj)`: custom init function. See `Custom Init` section below.
 - `adapt(host)`: custom adapt function.
 - `mode`: either `list` or `object`. default `list`.
 - `display`: either `active` or `all`. default `all`. Only applicable under `list` mode.
   - use to control whether to show all entries in the list, or only active one.
   - to toggle active entry, see `controls in below section.
 - `view`: object with following fields for different purpose view cfg object:
   - `common`: viewcfg for the whole widget
   - `entry`: viewcfg for each entry
 - `fields`: object containing fields of makeform definition. a sample fields object:

    {
      name: {type: "@makeform/input", meta: {isRequired: true}},
      desc: {type: "@makeform/textarea", meta: {isRequired: false, title: "description"}},
    }
 - `conditions`: an array of conditional control definition objects. See `Conditional Control Mechanism` below.
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
            pubsub.fire("@makeform/nest:init", obj)
        }

Where `obj` fired along with the `@makeform/nest:init` event to `@makeform/nest` via `pubsub` is described as above.

Note that you should overwrite `@makeform/nest`'s DOM and implement `widget` plug manually for ancestor `@makeform/common`.


## Controls

`@makeform/nest` provides additional control APIs:

 - `toggle({key})`: used in `active` display mode. toggle item with given key.


## Mixins

`@makeform/nest` uses `ldview` to render widgets, and an accompanying mixin kit is shipped along with this package. To use it:

    include @/@makeform/nest/mixin.pug
    +widget("your-widget-name")
    +vis("visibility-control-name")


Available mixins:

 - `widget(name)`: create a widget with specific name.
 - `vis(name)`: add a visibility control with specific name.


## ld selectors

 - `lng`: show this node only if current i18n language tag or code matches `data-lng` value.
 - `visibility`: show this node based on target name specified by `data-name` from condition controls.
 - `block`: node containing widget with name stored in `data-name` from `fields`.


## Conditional Control Mechanism

To support condition-based form behavior, we provide a *conditional control mechanism*, which is enabled by supplying the `conditions` field specified in the `@makeform/nest:init` event mentioned above.

The `conditions` field is an array of *conditional control definition objects* (also referred to as `rule object`), defined as below:

 - `src`: The key value in `fields` object corresponding to the widget this rule is based on.
   - This will be ignored or treated as a hint if `func` is provided.
 - `func(cfg)`: *optional* A function used when a more advanced rule is needed to determined whether this condition should be activated.
   - The `func` will be invoked once for each target in the `targets` array.
   - Parameter `cfg`: The `config` object described below.
   - Return value: `true` if the rule should be activated for the current target; otherwise `false1.
   - When used as a precondition, the rule will be considered activated *only if all targets return `true`*.
     - This behavior may be made configurable in the future.
 - `precond`: *optional* The id of another rule that serves as a precondition for this rule.
   - when specified, this rule is applied only if the precondition is active.
 - `id`: *optional* The unique identifier of this rule.
 - `config`: An object that determines how this rule should be applied. It includes the following fields:
   - `values`: An array of values used to match against the value of the widget specified by `src`.
     - When any of the values matches the wiget's value, the rule is considered active.
     - Ignored when `func` is provided.
   - `target`: An vinternally assigned field used by `func` to indicate the current target being evaluated.
     - Do not manually specify this field; it will be filled automatically.
   - `targets`: An array of strings indicating the field keys this rule applies to.
     - To support recursive conditional control, a target can be defined as an array of strings. See `Recursive Conditions` section below for more information.

Note: When there are conflicts between these rule objects, the later ones take precedence.

Additionally in `config` object, the following fields are applied when the rule is active:
 - `enabled`: Boolean. `true` to enable the target widget; otherwise disabled.
 - `disabled`: Boolean. `true` to disable the target widget; otherwise enabled.
 - `is-required`: Boolean. `true` to make the target widget as required; make it `not required` otherwise.
 - `readonly`: Boolean. `true` to make the target widget as readonly; make it `editable` otherwise.

Note:
 - If a field is omitted from the config, it will not be affected.
 - If the rule is not active but the field is specified, the inverse value will be applied instead.


### Recursive Conditions

To refer to a nested field (a field that is inside a `@makeform/nest` field), use an array of string representing the path to the target field. For example:

    ["contact", "phone", "mobile"]


A sample rule object that refers to some nested fields:

    {
      src: "type"
      config: {
        values: ["company"],
        targets: [
          "taxid",
          ["contact", "office phone"]
        ],
        enabled: true
      }
    }

### TBD: Controlling Parent Fields Based on Nested Fields

Since a parent widget can receive notifications when its nested fields change, it's possible to define a rule object in the parent that reacts to changes in its children - effectively enabling bottom-up conditional control.

However, referencing nested fields using an array of strings in the src field is not currently supported. This feature is planned for a future update.


## Custom Init

The `init` function that is sent into `@makeform/nest:init` will be called after `@makeform/nest` is inited with the widget object as `this` and internal `obj` passed as parameter, which contains following fields:

 - `activeKey`: key of the active tab, if widget is tab-based.
 - `entry`: an object storing each entry of this widget
   - in list mode, the entry key will be used as its key in this object
   - in object mode, check `active-key` for its key in `entry`.
 - `fields`: fields meta provided by child block.

Except fields list above, please consider all other fields as internal and prevent using them.


## `condctrl` Constructor

condctrl is used to dynamically change widget configuration based on current user input. Usage:

    cc = new condctrl({ conditions, fields, baseRule })

Constructor parameters:

 - `conditions`: An array of conditional rule objects.
 - `fields`: A key-value object of field definitions.
 - `baseRule`: (optional) a function to make a final change before conditions are applied. options:
   - `target`: target (path) name
   - `widget`: widget of the current target.
   - `meta`: meta of the current target.
   - `opt`: options when `apply` is called.


## License

MIT License
