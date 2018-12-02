# aws-ruby


### client_params

The AWS CLI (and SDK) expect stack parameters to be passed in a certain format.  This gem provides a utility method
called `client_params` that just asks for a simple ruby hash that it then converts to the format expected by the SDK.

```ruby
client_params(
  network_stack_name: network_stack_name,
  env_name: env_name,
  some_other_param: that_params_value,
  a_param_we_are_not_changing: :use_previous_value
)
```

Note that when this helper is used in a call to update a stack, you can use the special `:use_previous_value` value
and AWS will reuse the parameter value used in the last create or update stack call.
