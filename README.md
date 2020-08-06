https://hackmd.io/@ryanjbaxter/spring-on-k8s-workshop


# Getting started with Spring Cloud
Workshop Materials: [insert link]

Tim Ysewyn, Solutions Architect, VMware

## What you will do

- Define a contract between two applications
- Create a basic Spring Boot app
- Deploy and run the app on Kubernetes
- Configure an API gateway
- Make your application more resilient

## Prerequisites
Everyone will need:

- Basic knowledge of Spring and Kubernetes (we will not be giving an introduction to either)

If you are following these notes from an event all the pre-requisites will be provided in the Lab. You only need to worry about these if you are going to work through the lab on your own.

- [JDK 8 or higher](https://openjdk.java.net/install/index.html)
    - **Please ensure you have a JDK installed and not just a JRE**
- [Docker](https://docs.docker.com/install/) installed
- [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed
- [yq](https://mikefarah.gitbook.io/yq/)
- [Spring Boot CLI](https://docs.spring.io/spring-boot/docs/current/reference/html/getting-started.html#getting-started-installing-the-cli) and [Spring Cloud CLI](https://cloud.spring.io/spring-cloud-cli/reference/html/#_installation)
    - **Optional** - these will be used to showcase a feature in one of the Spring Cloud projects during this workshop.

### Doing the workshop on your own

- If you are doing this workshop on your own you will need to have your own Kubernetes cluster and Docker repo that the cluster can access
    - **Docker Desktop and Docker Hub** - Docker Desktop allows you to easily setup a local Kubernetes cluster ([Mac](https://docs.docker.com/docker-for-mac/#kubernetes), [Windows](https://docs.docker.com/docker-for-windows/#kubernetes)).
    This in combination with [Docker Hub](https://hub.docker.com/) should allow you to easily run through this workshop.
    - **Hosted Kubernetes Clusters and Repos** - Various cloud providers such as Google and Amazon offer options for running Kubernetes clusters and repos in the cloud.
    You will need to follow instructions from the cloud provider to provision the cluster and repo as well configuring `kubectl` to work with these clusters.

### Doing The Workshop in Strigo

- Login To Strigo.

- Configuring `git`. Run this command in the terminal:

```bash
$ git config --global user.name "<name>"
$ git config --global user.email "<email>"
```

- Configuring `kubectl`. Run this command in the terminal:

```bash
$ kind-setup
Cluster already active: kind
Setting up kubeconfig
```

- Run the below command to verify kubectl is configured correctly

```bash
$ kubectl cluster-info
Kubernetes master is running at https://127.0.0.1:43723
KubeDNS is running at https://127.0.0.1:43723/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

To further debug and diagnose cluster problems, use `'kubectl cluster-info dump'`.

> NOTE: it might take a minute or so after the VM launches to get the Kubernetes API server up and running, so your first few attempts at using kubectl may be very slow or fail.
After that it should be responsive.

### Setting up the environment

- Installing Kubernetes [Operator Lifecycle Manager](https://github.com/operator-framework/operator-lifecycle-manager)
    
    `curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/0.15.1/install.sh | bash -s 0.15.1`
    
        NOTE: Please check [the OLM releases](https://github.com/operator-framework/operator-lifecycle-manager/releases) to install the latest version.

- Kubernetes Operators (assuming your K8s cluster has internet access)

    - Prometheus Operator

        `kubectl create -f https://operatorhub.io/install/prometheus.yaml`

    - Grafana Operator (assuming internet access)

        `kubectl create -f https://operatorhub.io/install/alpha/grafana-operator.yaml`

    - Redis Operator (assuming internet access)

        `kubectl create -f https://operatorhub.io/install/redis-operator.yaml`

- Prometheus

    `kubectl create -f [link to yaml]`

- Grafana

    `kubectl create -f [link to yaml]`

- Redis

    `kubectl create -f [link to yaml]`

## Define and create a contract

The fastest way to showcase the API-first principle during this workshop is to create a new git repository which will contain all of our contracts which we agreed upon.

```bash
$ cd demo
$ mkdir contracts && cd contracts && git init
```

To define our contracts we'll use our first Spring Cloud project.
You might have guessed it, it's called `Spring Cloud Contract`.
Because the project is assuming a specific directory structure, we'll create this first.
The convention is like this: `META-INF/[groupId]/[artifactId]/[version]/contracts`.

Since the application we're going to create later will have a group id of `com.example`, an artifact id of `s1p-spring-cloud-demo-app` and `0.0.1-SNAPSHOT` as its version we'll have to execute the following command.

```bash
$ mkdir -p META-INF/com.example/s1p-spring-cloud-demo-app/0.0.1-SNAPSHOT/contracts
```

And so you should see the exact same output if you execute this command:

```bash
$ tree .
.
└── META-INF
    └── com.example
        └── s1p-spring-cloud-demo-app
            └── 0.0.1-SNAPSHOT
                └── contracts
```

Next we'll define our two contracts under the newly created directory.

META-INF/com.example/s1p-spring-cloud-demo-app/0.0.1-SNAPSHOT/contracts/getAllShopItems.groovy

```groovy
package contracts

org.springframework.cloud.contract.spec.Contract.make {
    request {
        method 'GET'
        url '/shop/items'
        headers {
            contentType('application/json')
        }
    }
    response {
        status OK()
        headers {
            contentType('application/json')
        }
        body([
            "pulled-pork": [
                "name": "Pulled pork",
                "img": "link",
                "price": 26,
            ],
            "brisket": [
                "name": "Brisket",
                "img": "link",
                "price": 22,
            ],
            "ribs": [
                "name": "Pork Ribs",
                "img": "link",
                "price": 20,
            ],
            "burnt-ends": [
                "name": "Pork Belly Burnt Ends",
                "img": "link",
                "price": 23,
            ],
        ])
    }
}
```

META-INF/com.example/s1p-spring-cloud-demo-app/0.0.1-SNAPSHOT/contracts/placeOrder.groovy

```groovy
package contracts

org.springframework.cloud.contract.spec.Contract.make {
    request {
        method 'POST'
        url '/shop/orders'
        headers {
            contentType('application/json')
        }
        body([
            "name": "John Doe",
            "items": [
                "pulled-pork": [
                    "count": 1
                ],
                "brisket": [
                    "count": 1
                ],
                "ribs": [
                    "count": 1
                ],
                "burnt-ends": [
                    "count": 1
                ],
            ],
        ])
    }
    response {
        status OK()
        headers {
            contentType('application/json')
        }
    }
}
```

And as a last step we'll commit our changes and push them to a remote

```bash
$ git add .
$ git commit -m 'Initial contracts'
$ git remote add origin <origin>
$ git push -u origin master
```

### Using the contract as stubs

> NOTE: This can't be done on the VM in the lab setting because of how the VM has been configured.
However you can install the `Spring Boot CLI` and `Spring Cloud CLI` on your local machine and give it a try!

From this point on our consumer can continue developing without any changes we need to make to our application.
Our defined contracts will be converted into stubs by the `Spring Cloud Contract Stubrunner`.
To let you see how this works we'll need to create a new file and use the second Spring Cloud project, `Spring Cloud CLI`.

Let's create a new file `stubrunner.yml`

```yaml
stubrunner:
  ids:
    - com.example:s1p-spring-cloud-demo-app:+:9876
  repositoryRoot: <git>
  generate-stubs: true
  stubs-mode: REMOTE
```

After creating the file run the following command in your terminal from the same directory where your `stubrunner.yml` file is located:

```bash
$ spring cloud stubrunner
```

If you visit `http://localhost:8750/stubs` you will find a list of all configured stubs.
```json
{
"com.example:s1p-spring-cloud-demo-app:+:stubs": 9876
}
```

Since we specified that our stubs need to be served on port `9876`, let's try to get our items.

```bash
$ http GET http://localhost:9876/shop/items content-type:application/json
HTTP/1.1 200 OK
Content-Encoding: gzip
Content-Type: application/json
Matched-Stub-Id: e2fc25be-3cd4-4117-9327-a23f44c25d54
Server: Jetty(9.4.20.v20190813)
Transfer-Encoding: chunked
Vary: Accept-Encoding, User-Agent

{
    "brisket": {
        "img": "link",
        "name": "Brisket",
        "price": 22
    },
    "burnt-ends": {
        "img": "link",
        "name": "Pork Belly Burnt Ends",
        "price": 23
    },
    "pulled-pork": {
        "img": "link",
        "name": "Pulled pork",
        "price": 26
    },
    "ribs": {
        "img": "link",
        "name": "Pork Ribs",
        "price": 20
    }
}
```

If we would visit the same link using our browser we get the following response:

```

                                               Request was not matched
                                               =======================

-----------------------------------------------------------------------------------------------------------------------
| Closest stub                                             | Request                                                  |
-----------------------------------------------------------------------------------------------------------------------
                                                           |
GET                                                        | GET
/shop/items                                                | /shop/items
                                                           |
Content-Type [matches] : application/json.*                |                                                     <<<<< Header is not present
                                                           |
                                                           |
-----------------------------------------------------------------------------------------------------------------------
```


## Create an app

In the Lab:

- Run these commands in your terminal (please copy them verbatim to make the rest of the lab run smoothly)

```bash
$ cd ~/demo && mkdir s1p-spring-cloud-demo-app && cd s1p-spring-cloud-demo-app
$ curl https://start.spring.io/starter.tgz -d artifactId=s1p-spring-cloud-demo-app -d name=s1p-spring-cloud-demo-app -d packageName=com.example.demo -d dependencies=web,actuator,cloud-contract-verifier -d javaVersion=11 | tar -xzf -
```

- Open the IDE using the “IDE” button at the top of the lab - it might be obscured by the “Call for Assistance” button.

Working on your own:

- Click [here](https://start.spring.io/starter.zip?type=maven-project&language=java&platformVersion=2.3.2.RELEASE&packaging=jar&jvmVersion=11&groupId=com.example&artifactId=s1p-spring-cloud-demo-app&name=s1p-spring-cloud-demo-app&description=Getting%20started%20with%20Spring%20Cloud&packageName=com.example.demo&dependencies=web,actuator,cloud-contract-verifier) to download a zip of the Spring Boot app
- Unzip the project to your desired workspace and open in your favorite IDE

### Implementing and verifying our API

If we would build and test our newly created application everything should be fine.

```bash
$ ./mvnw clean verify
...
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  16.974 s
[INFO] Finished at: 2020-08-05T14:38:04Z
[INFO] ------------------------------------------------------------------------
```

To validate our contracts against our new app we'll need to make some changes.
First we'll need to make a base class which will be used as the parent class for our generated tests.

Let's add a `BaseTestClass.java` under `src/test/java/com/example/demo`

```java
package com.example.demo;

import org.junit.jupiter.api.BeforeEach;

import io.restassured.module.mockmvc.RestAssuredMockMvc;

public class BaseTestClass {

    @BeforeEach
    public void setup() {
        RestAssuredMockMvc.standaloneSetup();
    }
}
```

Update the configuration of the `spring-cloud-contract-maven-plugin` in your `pom.xml` file and rerun your build.

```xml
<plugin>
    ...
    <configuration>
        <testFramework>JUNIT5</testFramework>

        <baseClassForTests>com.example.demo.BaseTestClass</baseClassForTests>

        <!-- We want to pick contracts from a Git repository -->
        <contractsRepositoryUrl>git://https://[uri]</contractsRepositoryUrl>
        
        <!-- We reuse the contract dependency section to set up the path
        to the folder that contains the contract definitions. In our case the
        path will be /groupId/artifactId/version/contracts -->
        <contractDependency>
            <groupId>${project.groupId}</groupId>
            <artifactId>${project.artifactId}</artifactId>
            <version>${project.version}</version>
        </contractDependency>

        <!-- The contracts mode can't be classpath -->
        <contractsMode>REMOTE</contractsMode>
    </configuration>
</plugin>
```

After rerunning your build you should see an output similar to this one:

```bash
[ERROR] Failures: 
[ERROR]   ContractsTest.validate_getAllShopItems:30 
Expecting:
 <404>
to be equal to:
 <200>
but was not.
[ERROR]   ContractsTest.validate_placeOrder:48 
Expecting:
 <404>
to be equal to:
 <200>
but was not.
[INFO] 
[ERROR] Tests run: 3, Failures: 2, Errors: 0, Skipped: 0
```

## Build and run the app

> NOTE: Use Spring Boot 2.3 CNB feature, push to Docker Hub and deploy to K8s using Kustomize


## Create an API gateway

> NOTE: define route using K8s DNS


## Make your application more resilient

### Rate limiting

Let's say this is the first version of our API which doesn't have authentication or authorization.
Along comes this hacker who wants to hurt us by sending a huge amount of requests to our application.
One of the first things we can do is to add a rate limiter to our API gateway so the requests of the hacker are not being sent to our application anymore.

> NOTE: based on the originating IP address

### Circuit breaker

TODO

- Add dependencies
- Configure initial setup
- Run test script

Now let's scale our application and try to see if we can still open our circuit.

TODO

- Scale deployment to 2 instances
- Configure one instance to behave inconsistently using actuator endpoint
- Run test script again

As you can see the circuit breaker won't go in an open state as long as there is one instance which can successfully process the request.
But this means all of our requests can still be routed to any failing instance!
Why is that?
Our gateway doesn't have the ability to recognize the different instances and their individual state because we're using the load balancer behind the DNS on Kubernetes to route our request to one of our application instances.

### Load Balancing

In order to send our requests only to a healthy instance we can make use of client-side load balancing, meaning our gateway will decide which instance we're going to target.

TODO

- Add/enable service discovery dependency
- Use `HealthCheckServiceInstanceListSupplier`
- Adapt the route
- Run test script a third time


## Follow-up resources

- [Spring on Kubernetes!](https://hackmd.io/@ryanjbaxter/spring-on-k8s-workshop)
- [Spring Cloud Contract](link to Marcin's course)
- [The CI/CD Experience: Kubernetes Edition](https://springonetour.io/2020/cicd)
- [VMware Tanzu PAL for Java Developers](https://tanzu.vmware.com/platform-acceleration-lab/pal-for-developers-java)
- [VMware Tanzu PAL for Java Application Architects](https://tanzu.vmware.com/platform-acceleration-lab/pal-for-architects-java)
