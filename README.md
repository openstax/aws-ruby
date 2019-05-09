# aws-ruby

[![Build Status](https://travis-ci.org/openstax/aws-ruby.svg?branch=master)](https://travis-ci.org/openstax/aws-ruby)

The `openstax_aws` gem helps you deploy your applications to AWS using CloudFormation.  It provides a layer on top of
the AWS SDKs to help coordinate common deployment steps and configurations.

The gem also includes utilities that use Packer and Ansible to help you build Amazon Machine Images (AMIs).

When using CloudFormation directly, you write template files that define AWS resources and their interconnections.  You
then make AWS API calls (either using the AWS CLI directly or one of the AWS SDKs) that tell AWS to build the resources
defined in those templates.  The resulting set of resources is called a stack.  The API calls involved are numerous and
repetitive.

In this gem, you don't make the AWS API calls directly.  Instead, you make "deployment" objects that organize and act on
sets of "stack" objects.  While not required to benefit from this gem, DSLs, convenience methods, and conventions let you
adopt a "convention over configuration" approach to dry up your code.

## A Quick Look

Let's assume we have a web API application defined in two CloudFormation templates: `app.yml` for the web server template
and `network.yml` for a template that sets up VPCs, subnets, etc.  The `app.yml` template defines one `ImageId` parameter
that is the AMI ID for the web server code and also connects to the network template by importing some of its values.
There is one Ruby file defining the deployment object, `web_api_deployment.rb`. And then there's an executable script to
call a method on the deployment, `create_deployment.rb`. Though not required, let's further assume that all files are in
the same directory:

```
/myapp $> ls
app.yml
network.yml
web_api_deployment.rb
create_deployment.rb
```

```ruby
# web_api_deployment.rb

class WebApiDeployment < OpenStax::Aws::DeploymentBase
  template_directory __dir__

  stack :network
  stack :app

  def initialize(env_name:, region:, dry_run: true)
    super(name: "web-api", env_name: env_name, region: region, dry_run: dry_run)
  end

  def create(api_image_id)
    network_stack.create(wait: true)
    app_stack.create(image_id: api_image_id)
  end
end
```

```ruby
# create_deployment.rb

deployment = WebApiDeployment.new(env_name: "production", region: "us-east-1", dry_run: false)
deployment.create("ami-0f71234567890a7f2")
```

Now let's call the script (making sure our AWS secrets are populated into our environment):

```
/myapp $> ./create_deployment.rb
I, [2019-04-26T09:13:58.133753 #12173]  INFO -- : Creating production-web-api-network stack...
D, [2019-04-26T09:14:29.543717 #12173] DEBUG -- : Waiting for production-web-api-network stack to be created... (0m30s elapsed)
D, [2019-04-26T09:14:59.923172 #12173] DEBUG -- : Waiting for production-web-api-network stack to be created... (1m1s elapsed)
I, [2019-04-26T09:15:00.306983 #12173]  INFO -- : production-web-api-network has been created!
I, [2019-04-26T09:15:01.133753 #12173]  INFO -- : Creating production-web-api-app stack...
D, [2019-04-26T09:15:31.543717 #12173] DEBUG -- : Waiting for production-web-api-app stack to be created... (0m30s elapsed)
D, [2019-04-26T09:16:01.923172 #12173] DEBUG -- : Waiting for production-web-api-app stack to be created... (1m1s elapsed)
I, [2019-04-26T09:16:02.306983 #12173]  INFO -- : production-web-api-app has been created!
```

That's it.  Now you have two stacks deployed with minimal fuss.  Behind the scenes, the gem found your
templates, validated them, uploaded them to S3, populated inferred template parameters and capabilities, made
standardized stack names, managed instance key pairs, waited for stacks to complete, and more.
Major functionality not shown in this example are the methods for updating and deleting deployments, as well as the mechanism for
conveying secret values to instances.

## Deployments & Stacks

In a deployment supported by this gem, `Stack` objects do the heavy lifting of calling CloudFormation APIs.
Deployment objects contain a number of `Stack`s and coordinate their use to effect the creation, updating, and
deletion of applications and infrastructure. For each application or separable infrastructure you'll have a
deployment class that inherits from `OpenStax::Aws::DeploymentBase`.

### Defining stacks (manually)

You can instantiate `OpenStax::Aws::Stack` objects directly.  E.g. your deployment class may look like:

```ruby
class MyDeployment < OpenStax::Aws::DeploymentBase

  attr_reader :network_stack, :app_stack

  def initialize(env_name:, name:, region:, dry_run:)
    super(env_name: env_name, name: name, region: region, dry_run: dry_run)

    @network_stack = OpenStax::Aws::Stack.new(
      name: "#{env_name}-#{name}-network",
      region: region,
      absolute_template_path: File.join(__dir__, "../../templates/network.yml"),
      enable_termination_protection: env_name == "production",
      parameter_defaults: {
        env_name: env_name
      },
      dry_run: dry_run
    )

    @app_stack = OpenStax::Aws::Stack.new(
      name: "#{env_name}-#{name}-app",
      region: region,
      absolute_template_path: File.join(__dir__, "../../templates/app.yml"),
      enable_termination_protection: env_name == "production",
      parameter_defaults: {
        env_name: env_name,
        network_stack_name: @network_stack.name,
      },
      dry_run: dry_run
    )
  end

  def create(app_image_id)
    @network_stack.create(wait: true)
    @app_stack.create(params: {image_id: app_image_id})
  end
end
```

You create instance variables, make them accessible via `attr_reader` and set a bunch of options.
A lot of these options end up being duplicated, and when you get into a deployment that has a bunch
of stacks, this duplication gets a bit heavy.

### Defining stacks (using the DSL)

This gem provides an alternative way to declare stacks.  The following code is equivalent to the
manual use of stacks above:

```ruby
class MyDeployment < OpenStax::Aws::DeploymentBase

  template_directory __dir__, "../../templates"

  stack :network
  stack :app

  def initialize(env_name:, name:, region:, dry_run:)
    super(env_name: env_name, name: name, region: region, dry_run: dry_run)
  end

  def create(app_image_id)
    network_stack.create(wait: true)
    app_stack.create(params: {image_id: app_image_id})
  end
end
```

Here, we've removed a good bit of code by calling the `stack` class method to define our two
stacks.  The `stack` method uses knowledge of the deployment in which it is called in addition
to some conventions to fill in smart defaults for many of the stack options.

* It makes the `:network` stack accessible via `network_stack`.
* It standardizes the stack name in AWS as `env_name-deployment_name-stack_symbol`.
* It sets the stack region to the the deployment's region.
* For the `:network` stack, it automatically finds template files named `network.yml` or `network.json`
in the declared `template_directory`.
* It enables stack termination protection if the deployment's environment name is the
production environment name (which itself is configured in the settings).
* It set's the stack's `dry_run` field to the deployment's `dry_run` value.
* It detects standard parameters in the template that it knows the values for, e.g. `EnvName`,
`KeyName` (or `KeyPairName`), and `[Anything]StackName` and fills in those values as the
stack's parameter defaults.

If you don't want to use this automagic setting of values, you can manually define a few of them:

```ruby
stack :app do
  region { "us-west-2" }
  absolute_template_path { File.join(__dir__, "../../templates/app_variant.yml") }
  parameter_defaults do
    env_name { "april-11-b" }
  end
end
```

Blocks passed to the stack definition methods (like `region` above) are executed in the context of the
containing deployment object.

When using the DSL, you can define a stack-local `template_directory` to override the deployment-level
one, e.g.

```ruby
stack :app do
  template_directory __dir__, "../somewhere/else"
end
```

You can also set a relative template path to override the inferred template filename (can be done
with or without local modification of the template directory):

```ruby
stack :app do
  relative_template_path "foo/app_2.yml"
end
```

### Working with stacks

Whichever way you choose to define your stack, your next step is to call methods to create, update, and
delete your stacks in AWS.  You do this with the `Stack` methods `create`, `apply_change_set`, and
`delete`.

Each of these methods takes a `wait` boolean (defaults to `false`), which will wait for the
operation to complete in AWS before returning.  You can also separately make a call to wait for stack
operations to complete, which is useful when you want to simultaneously run operations in several independent stacks
and then wait for all of them at the same time, e.g.

```ruby
network_stack.create   # these return immediately after starting the creation in AWS
sqs_stack.create       # (meaning all three happen concurrently)
dynamodb_stack.create

network_stack.wait_for_creation  # blocks until network_stack created
sqs_stack.wait_for_creation      # blocks until sqs_stack created (may have finished already)
dynamodb_stack.wait_for_creation
```

There are three waiter methods on `Stack`: `wait_for_creation`, `wait_for_update`, `wait_for_deletion`.

Other things to know about stacks:

* You can get stack output values by calling `my_stack.output_value(key: "whatever-the-key-is")`
* Stack parameter names are typically camel-cased in the template, but in Ruby we write them
underscored, so e.g. a `EnvName` parameter in the template is referred to in the ruby code as
`env_name`.  You'll also have noticed that the way we pass parameters is simplified so that we just
have to use Ruby hashes instead of the more verbose `ParameterKey` `ParameterValue` breakdown
used in the SDK.

#### `create`

[ Work on this section ]

#### `apply_change_set`

[ Work on this section ]

When updating a stack, call `apply_change_set` with just the parameters you want to change.  The gem will build the
parameters to include in the update using the following algorithm:

1. First, every parameter in the currently-deployed stack that is also in the template being used in
the update will be included with a value of `:use_previous_value`.
2. Next, those parameters in the template being used in the update that are not already in the deployed
stack will be included with a default value defined in the stack definition (in the `parameter_defaults` block)
3. Next, "volatile parameters" are set. Volatile parameters are those that can change outside of stack updates (e.g. autoscaling group desired
capacities that change due to scaling events).  See below for more of a discussion of volatile parameters.
Volatile parameters will override any existing parameter values.
4. Finally, parameters explicitly set in the call to `apply_change_set` will be included.  These values
will override any existing parameter values.

Any parameter that ends up with a `nil` value after these series of steps will be removed.  Those parameters
will need to have a default value set in the CloudFormation template file to avoid the call failing within AWS.

##### `parameter_defaults`

Use the `parameter_defaults` section of the stack defintion to give default values for stack parameters.
Entries within the block are of the form `parameter_name value` or `parameter_name { value }`.  When the
latter block form is used, the block is executed in the context of the stack's deployment object when
the stack is first accessed.

```ruby
stack :app do
  ...
  parameter_defaults do
    web_server_desired_capacity 2
    some_other_parameter_name { "#{env_name}-blah" }
  end
  ...
end
```

Deployment-wide parameter defaults can be defined via a `parameter_defaults(parameter_name)` method on your
deployment class.  This method should return the default value given a parameter name (as it is shown in
the template), e.g.

```ruby
class MyDeployment < OpenStax::Aws::DeploymentBase
  ...
  def parameter_default(parameter_name)
    "my-log-bucket" if parameter_name == "LogBucketName"
  end
  ...
end
```

The `OpenStax::Aws::DeploymentBase` class provides a `built_in_parameter_default(parameter_name)` method
for some baseline defaults, e.g. for `"EnvName"` and parameters that are names of other stacks.  If you
want to disable these extra defaults, you can override the method and have it return nil.

```ruby
class MyDeployment < OpenStax::Aws::DeploymentBase
  ...
  def built_in_parameter_default(parameter_name)
    nil
  end
  ...
end
```

##### `volatile_parameters`

By and large, we want to make changes to our stacks using the update stack capabilities offered by AWS.
However, sometimes there are parameters that change outside of this update process.  The classic example
is autoscaling group desired capacity.  When we define an ASG in a template, we define its desired capacity
(if we don't, it defaults to the minimum allowed capacity).  If we give its desired capacity as a static number,
it'll have that value for each update, meaning that if we create it with a desired capacity of '2' and then
a scaling event causes the desired capacity to change to 6, an update through CloudFormation will reset the
desired capacity to 2.  Even if the capacity is not a literal number but instead a stack parameter, a stack
update call that uses the "use previous value" functionality will use the value last used during a stack update
and not the current value of the desired capacity in the stack.  What we want to do is get the stack's current
desired capacity and use that value in the stack update call so that the update leaves the capacity unchanged.

Volatile parameters let us do that.  They define the parameters that can change outside of stack updates and
define a block of code to run just before the update to get that latest value.  That value is then used in the
stack update.  The form within the `volatile_parameters` block is `parameter_name { value }` where the `{ value }`
block is executed in the context of the stack object, just before the call to update the stack.

```ruby
stack :app do
  ...
  volatile_parameters do
    web_server_desired_capacity { resource("Asg").desired_capacity }
  end
  ...
end
```

Here, we're getting the resource in our stack with the `Asg` logical ID (which returns an `Aws::AutoScaling::Group`
instance) and then getting its desired capacity.

#### `delete`

No options here besides `wait`.

### Dry runs

You'll have noticed above that deployment and `Stack` objects are instantiated with a `dry_run` parameter
that defaults to `true`.  When `dry_run` is true, stacks are not created, updated, or deleted, but the
code is exercised and log messages are generated.  Note that during dry run updates, CloudFormation change
sets are temporarily created on AWS but they are not executed.

### Configuration

You can configure gem behavior with:

```ruby
OpenStax::Aws.configure do |config|
  # The bucket where you want to upload templates
  config.cfn_template_bucket_name = "some-bucket-name"
  # The top-level folder(s) where templates are stored in the template bucket.
  # (default: "cfn_templates")
  config.cfn_template_bucket_folder = "cfn_templates"
  # A logger object, e.g. `Logger.new(STDOUT)` (the default); see below for more.
  config.logger = Logger.new(STDOUT)
  # The number of seconds the gem waits between polling for the completion of stack creation,
  # updates, deletes. (default: 30)
  config.stack_waiter_delay = 30
  # If true, the gem will parse your template and autoset the required capabilities
  # (default: true)
  config.infer_stack_capabilities = true
  # If true, the gem will set default values for parameters that it knows about (e.g.
  # EnvName, default: true)
  config.infer_parameter_defaults = true
  # The environment name you use for production, e.g. "prod" or "production" (the default).
  config.production_env_name = "production"
end
```

We use the logger configuration below:

```ruby
config.logger = Logger.new(STDOUT)
config.logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S.%3N")
  if severity == "INFO" or severity == "WARN"
      "[#{date_format}] #{severity}  | #{msg}\n"
  else
      "[#{date_format}] #{severity} | #{msg}\n"
  end
end
```

### Templates

While you won't usually use it directly, there is an `OpenStax::Aws::Template` object that you can
use to get values back from your template.  A stack's template is available via `my_stack.template`.
Templates are uploaded to S3 when its `Stack` needs it to be there.  Before it is uploaded, it is
validated and errors are raised to you.

### Other deployment methods and utilities

[ Work on this section ]

### README Todos

1. Discuss use of multiple parameters objects
