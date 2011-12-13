# VMC Knife
Extensions for vmc: the VMware Cloud CLI; the command line interface to VMware's Application Platform

MIT license

## Usecase
Prepare a file that describes the list of applications to deploy, their settings, their environment variables, required data-services and names, build file for the apps.
Run the deployment file on the command: will either install update, modify the apps on the cloudfoundry.
Run the deployment file via a web-interface.

    prepare a vmc deployment file.
    vmc_knife vmc_deployment_file.json

## Installation
ssh into a Cloudfoundry VM
load the cloudfoundry profile: source /home/ubuntu/.cloudfoundry_deployment_local
gem install vmc_knife

Or to install from source:
git clone https://github.com/hmalphettes/vmc-knife.git
cd vmc-knife
gem build vmc_knife.gemspec
gem install vmc_knife

## Example:
Create a recipe with the mongodb app example and the sinatra example app.
Make a new file example_recipe.json
Enter:
  {
    "sub_domain": "vcap.me",
    "target": "api.vcap.me",
    "email": "vcap@vcap.me",
    "password": "vcap",
    "recipes": [
      {
        "name": "example_recipe",
        "data_services": {
          "mongo1": {
            "name": "a_mongo",
            "vendor": "mongodb"
          }
        },
        "applications": {
          "example_mongo": {
            "name": "mongo_db_demo",
            "uris": [
              "mongodb-on-cf-demo.#{this['sub_domain']}"
            ],
            "staging": {
              "stack": "ruby19",
              "model": "rails3"
            },
            "resources": {
              "memory": 256
            },
            "services": [
              "#{this['recipes'][0]['data_services']['mongo1']['name']}"
            ],
            "env": [
              "DERIVED_VALUE_EXAMPLE=http://#{this['recipes'][0]['applications']['example_mongo']['uris'][0]}"
            ],
            "repository": {
              "url": "https://github.com/mccrory/cloud-foundry-mongodb-demo.git",
              "branch":"master"
            }
          }
        }
      }
    ]
  }

Navigate to the folder where the recipe is located.
And use vmc_knife:
  vmc_knife login
  vmc_knife configure-apps
  vmc_knife upload-apps
  vmc_knife start-apps

The console will look like this:

  ubuntu@ubuntu:~/tmp$ vmc_knife configure-apps
  Applications selected mongo_db_demo
  Data-services selected a_mongo
  {
    "applications": {
      "mongo_db_demo": {
        "name": "Create mongo_db_demo",
        "services": {
          "add": [
            "a_mongo"
          ]
        },
        "env": {
          "add": [
            "DERIVED_VALUE_EXAMPLE=http://mongodb-on-cf-demo.vcap.me"
          ]
        },
        "uris": {
          "add": [
            "mongodb-on-cf-demo.vcap.me"
          ]
        },
        "memory": " => 256"
      }
    }
  }
  Creating mongo_db_demo with {:name=>"mongo_db_demo", "resources"=>{"memory"=>256}, "staging"=>{"model"=>"rails3", "stack"=>"ruby19"}, "uris"=>["mongodb-on-cf-demo.vcap.me"], "services"=>["a_mongo"], "env"=>["DERIVED_VALUE_EXAMPLE=http://mongodb-on-cf-demo.vcap.me"]}

  ubuntu@ubuntu:~/tmp$ vmc_knife upload-apps
  Applications selected mongo_db_demo
  Data-services selected a_mongo
  Dir.entries(/home/ubuntu/vmc_knife_downloads/mongo_db_demo).size 2
  remote: Counting objects: 85, done.
  remote: Compressing objects: 100% (65/65), done.
  remote: Total 85 (delta 4), reused 84 (delta 4)
  Unpacking objects: 100% (85/85), done.
  fatal: Not a git repository (or any of the parent directories): .git
  Uploading Application mongo_db_demo from /home/ubuntu/vmc_knife_downloads/mongo_db_demo:
  Copying the files
  Done copying the files
    Checking for available resources: About to compute the fingerprints
  Finished computing the fingerprints
  Invoking check_resources with the fingerprints
  OK
    Processing resources: OK
    Packing application: OK
    Uploading (255K): client.upload_app about to start
    Uploading (255K): OK   
  Done client.upload_app
  Push Status: OK



Updating an app:
For example edit the memory parameter of the app. Then call:
  vmc_knife configure-apps
  vmc_knife restart-apps example_mongo

Note that vmc_knife's start/stop/restart only sends the command to vcap's cloud_controller.
It does not try to poll it to see if the command was successful.

In progress:
Accessing the data-services:
Assuming that vmc_knife is able to locate the cloud_controller.yml and mongo binary:
  vmc_knife data-shell mongo1
will drop the user to the mongo shell.

With postgresql export and import are supported.

Todo: take advantage of the new vmc-tunnel.
