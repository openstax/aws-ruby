### Better declaration of stacks

```ruby
class MyDeployment < OpenStax::Aws::DeploymentBase
    template_directory __dir__, "../../../cfn/search/"

    # makes an attr_reader `elasticsearch_stack`
    stack :elasticsearch, # can infer stack name
          template_path: "elasticsearch.yml",
          capabilities: [:iam],
          default_parameters: -> {
            env_name: env_name # could even have multiple passes of defaults, some set from DeploymentBase (e.g. env_name)
          }
end
```
