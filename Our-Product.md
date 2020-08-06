# Our Product

## Table of Contents

* [Defining and Creating the Contracts](#defining-and-creating-the-contracts)
* [Mocking the API](#mocking-the-api)
* [Implementing the API](#implementing-the-api)
    * [Configuring Our Contract Tests](#configuring-our-contract-tests)
    * [Implementing and Verifying our API](#implementing-and-verifying-our-api)
* [Deploying Our Application](#deploying-our-application)
    * [Enabling Additional Features](#enabling-additional-features)
    * [Building an Image](#building-an-image)
    * [Putting the Image in a Registry](#putting-the-image-in-a-registry)
    * [Running the Build and Pushing the Image](#running-the-build-and-pushing-the-image)
    * [Deploying the Application on Kubernetes](#deploying-the-application-on-kubernetes)
* [Testing Our Application](#testing-our-application)

## Defining and Creating the Contracts

The fastest way to showcase the API-first principle during this workshop is to create a new git repository to contain all of the contracts we agreed upon:

```bash
$ mkdir -p ~/demo/contracts && cd ~/demo/contracts
$ git init
```

To define our contracts, we will use our first Spring Cloud project.
You might have guessed it: It is called `Spring Cloud Contract`.
Because the project is assuming a specific directory structure, we will create this first.
The convention is: `META-INF/[groupId]/[artifactId]/[version]/contracts`.

Since the application we are going to create later will have a group ID of `com.example.demo`, an artifact ID of `shop`, and `0.0.1-SNAPSHOT` as its version, we will have to execute the following command:

```bash
$ mkdir -p META-INF/com.example.demo/shop/0.0.1-SNAPSHOT/contracts
```

You should see the exact same output if you run this command:

```bash
$ tree .
.
└── META-INF
    └── com.example.demo
        └── shop
            └── 0.0.1-SNAPSHOT
                └── contracts
```

Next, we will define our two contracts under the newly created directory.

`META-INF/com.example.demo/shop/0.0.1-SNAPSHOT/contracts/getCatalogItems.groovy`

```groovy
package contracts

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    request {
        method 'GET'
        url '/catalog/items'
        headers {
            accept('application/json')
        }
    }
    response {
        status OK()
        headers {
            contentType('application/json')
        }
        body([
            [
                "id": "6b76148d-0fda-4ebf-8966-d91bfaeb0236",
                "name": "Breakfast with homemade bread",
                "img": "https://images.unsplash.com/photo-1590688178590-bb8370b70528",
                "price": 16,
            ],
            [
                "id": "52d59380-79da-49d5-9d09-9716e20ccbc4",
                "name": "Brisket",
                "img": "https://images.unsplash.com/photo-1592894869086-f828b161e90a",
                "price": 24,
            ],
            [
                "id": "a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4",
                "name": "Pork Ribs",
                "img": "https://images.unsplash.com/photo-1544025162-d76694265947",
                "price": 20,
            ],
        ])
        bodyMatchers {
            jsonPath('$', byType { minOccurrence(1) })
            jsonPath('$[*].id', byRegex(uuid()))
            jsonPath('$[*].name', byRegex("[a-zA-Z \\-]+"))
            jsonPath('$[*].img', byRegex(url()))
            jsonPath('$[*].price', byRegex(positiveInt()))
        }
    }
}
```

`META-INF/com.example.demo/shop/0.0.1-SNAPSHOT/contracts/placeOrder.groovy`

```groovy
package contracts

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    request {
        method 'POST'
        url '/orders'
        headers {
            contentType('application/json')
        }
        body(
            "name": $(consumer(regex('[^0-9\\_\\!\\¡\\?\\÷\\?\\¿\\/\\+\\=\\@\\#\$\\%\\ˆ\\&\\*\\(\\)\\{\\}\\|\\~\\<\\>\\;\\:\\[\\]]{2,}')), producer('Jane Doe')),
            "items": [
                [
                    "id": "6b76148d-0fda-4ebf-8966-d91bfaeb0236",
                    "amount": 1
                ],
            ],
        )
        bodyMatchers {
            jsonPath('$.items', byType { minOccurrence(1) })
            jsonPath('$.items[0].id', byRegex(uuid()))
            jsonPath('$.items[0].amount', byRegex(positiveInt()))
        }
    }
    response {
        status CREATED()
        headers {
            header('Location', $(consumer('/orders/9bb544af-3df5-476b-bff9-17984e8e5e0a'),
                producer(regex('\\/orders\\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'))))
        }
    }
}
```

Finally, we will commit our changes and push them to a remote repository:

```bash
$ git add .
$ git commit -m 'Initial contracts'
$ git remote add origin <origin>
$ git push -u origin master
```

## Mocking the API

> NOTE: This cannot be done on the VM in the lab setting because of how the VM has been configured.
However, you can install the [Spring Boot CLI](https://docs.spring.io/spring-boot/docs/current/reference/html/getting-started.html#getting-started-installing-the-cli) and [Spring Cloud CLI](https://cloud.spring.io/spring-cloud-cli/reference/html/#_installation) on your local machine and give it a try!

From this point on, our consumer can continue developing without any changes to our application.
Our defined contracts will be converted into stubs by the `Spring Cloud Contract Stubrunner`.
To let you see how this works, we will need to create a new file and use the second Spring Cloud project, `Spring Cloud CLI`.

Let's create a new file `stubrunner.yml`:

```yaml
stubrunner:
  ids:
    - com.example.demo:shop:+:9876
  repositoryRoot: git://<git>
  generate-stubs: true
  stubs-mode: REMOTE
```

After creating the file, run the following command in your terminal from the same directory where your `stubrunner.yml` file is located:

```bash
$ spring cloud stubrunner
```

If you visit `http://localhost:8750/stubs`, you will find a list of all configured stubs:
```json
{
"com.example:shop:+:stubs": 9876
}
```

Since we specified that our stubs need to be served on port `9876`, we can try to get our items:

```bash
$ http GET http://localhost:9876/catalog/items accept:application/jsonHTTP/1.1 200 OK
Content-Encoding: gzip
Content-Type: application/json
Matched-Stub-Id: 3a8afb15-85cb-4aab-a9e8-dfdae341dfe4
Server: Jetty(9.4.20.v20190813)
Transfer-Encoding: chunked
Vary: Accept-Encoding, User-Agent

[
    {
        "id": "6b76148d-0fda-4ebf-8966-d91bfaeb0236",
        "img": "https://images.unsplash.com/photo-1590688178590-bb8370b70528",
        "name": "Breakfast with homemade bread",
        "price": 16
    },
    {
        "id": "52d59380-79da-49d5-9d09-9716e20ccbc4",
        "img": "https://images.unsplash.com/photo-1592894869086-f828b161e90a",
        "name": "Brisket",
        "price": 24
    },
    {
        "id": "a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4",
        "img": "https://images.unsplash.com/photo-1544025162-d76694265947",
        "name": "Pork Ribs",
        "price": 20
    }
]
```

If we visit the same link in our browser, we get the following response:

```
                                               Request was not matched
                                               =======================

-----------------------------------------------------------------------------------------------------------------------
| Closest stub                                             | Request                                                  |
-----------------------------------------------------------------------------------------------------------------------
                                                           |
GET                                                        | GET
/catalog/items                                             | /catalog/items
                                                           |
Accept [matches] : application/json.*                      | Accept:                                             <<<<< Header does not match
                                                           | text/html,application/xhtml+xml,application/xml;q=0.9,ima
                                                           | ge/webp,image/apng,*/*;q=0.8,application/signed-exchange;
                                                           | v=b3
                                                           |
                                                           |
-----------------------------------------------------------------------------------------------------------------------
```

## Implementing the API

In the Lab:

1. Run the following commands in your terminal (copy them verbatim to make the rest of the lab run smoothly):

```bash
$ mkdir -p ~/demo/shop && cd ~/demo/shop
$ curl https://start.spring.io/starter.tgz -d groupId=com.example.demo -d artifactId=shop -d name=shop -d description=Getting%20started%20with%20Spring%20Cloud%20-%20Shop -d packageName=com.example.demo.shop -d dependencies=web,actuator,cloud-contract-verifier,cloud-starter-sleuth -d javaVersion=11 | tar -xzf -
```

2. Open the IDE using the “IDE” button at the top of the lab - it might be obscured by the “Call for Assistance” button.

Working on your own:

1. Click [here](https://start.spring.io/starter.zip?type=maven-project&language=java&platformVersion=2.3.3.RELEASE&packaging=jar&jvmVersion=11&groupId=com.example.demo&artifactId=shop&name=shop&description=Getting%20started%20with%20Spring%20Cloud%20-%20Shop&packageName=com.example.demo.shop&dependencies=web,actuator,cloud-contract-verifier,cloud-starter-sleuth) to download a zip of the Spring Boot app
1. Unzip the project to your desired workspace and open in your favorite IDE

### Configuring Our Contract Tests

If we build and test our newly created application, everything should be fine:

```bash
$ ./mvnw clean verify
...
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
...
```

To validate our contracts against our new application, we will need to make some changes.
First, we will need to make a base class, which will be used as the parent class for our generated tests:

We can add a `BaseTestClass.java` under `src/test/java/com/example/demo/shop`

```java
package com.example.demo.shop;

import org.junit.jupiter.api.BeforeEach;

import io.restassured.module.mockmvc.RestAssuredMockMvc;

public class BaseTestClass {

    @BeforeEach
    public void setup() {
        RestAssuredMockMvc.standaloneSetup();
    }
}
```

Update the configuration of the `spring-cloud-contract-maven-plugin` plugin in your `pom.xml` file and rerun your build:

```xml
<plugin>
    ...
    <configuration>
        <testFramework>JUNIT5</testFramework>

        <baseClassForTests>com.example.demo.shop.BaseTestClass</baseClassForTests>

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

After re-running your build, you should see an output similar to this one:

```
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

### Implementing and Verifying our API

Okay! Now we're sure that we're verifying our API it's time to fix our failing tests.
As a first iteration we'll create a `CatalogController` and `OrdersController` which will react and respond to the requests our generated test will execute.

Add `CatalogController.java` to `src/main/java/com/example/demo/shop/catalog`

```java
package com.example.demo.shop.catalog;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/catalog")
public class CatalogController {

    public static final Logger logger = LoggerFactory.getLogger(CatalogController.class);

    @GetMapping(value = "/items", produces = { "application/json" })
    public ResponseEntity<String> retrieveAllItems() {
        logger.info("Received request for shop items");
        return ResponseEntity.ok().body("[{ \"id\": \"6b76148d-0fda-4ebf-8966-d91bfaeb0236\", \"img\": \"https://images.unsplash.com/photo-1590688178590-bb8370b70528\", \"name\": \"Breakfast with homemade bread\", \"price\": 16 }, { \"id\": \"52d59380-79da-49d5-9d09-9716e20ccbc4\", \"img\": \"https://images.unsplash.com/photo-1592894869086-f828b161e90a\", \"name\": \"Brisket\", \"price\": 24 }, { \"id\": \"a7be01f8-b76e-4384-bf1d-e69d7bdbe4b4\", \"img\": \"https://images.unsplash.com/photo-1544025162-d76694265947\", \"name\": \"Pork Ribs\", \"price\": 20 }]");
    }
    
}
```

Add `OrdersController.java` to `src/main/java/com/example/demo/shop/orders`

```java
package com.example.demo.shop.orders;

import java.net.URI;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/orders")
public class OrdersController {

    public static final Logger logger = LoggerFactory.getLogger(OrdersController.class);

    @PostMapping(consumes = { "application/json" })
    public ResponseEntity<Void> placeOrder() {
        UUID orderId = UUID.randomUUID();
        logger.info("Created order with id {}", orderId);
        return ResponseEntity.created(URI.create("/orders/" + orderId)).build();
    }
    
}
```

And update `BaseTestClass.java`

```java
package com.example.demo.shop;

import org.junit.jupiter.api.BeforeEach;

import io.restassured.module.mockmvc.RestAssuredMockMvc;
import com.example.demo.shop.catalog.CatalogController;
import com.example.demo.shop.orders.OrdersController;

public class BaseTestClass {

    @BeforeEach
    public void setup() {
        RestAssuredMockMvc.standaloneSetup(new CatalogController(), new OrdersController());
    }
    
}
```

If we run our build again we should see that our application is adhering to the contracts.

```bash
$ ./mvnw clean verify
...
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
...
```

## Deploying Our Application

During the lab we will deploy our application on Kubernetes.

### Enabling Additional Features

Spring Boot 2.3.x comes with additional features which can be of help when running on Kubernetes.
One of those functionalities is the graceful shutdown of your embedded application server so that running requests can be completed before Kubernetes kills your pod.
To enable this functionality you need to add the following line to `application.properties`:

```properties
server.shutdown=graceful
```

### Building an Image

Spring Boot 2.3.x can build an image for you without the need for any additional plugins or files.
To do this use the Spring Boot Build plugin goal `build-image`

```bash
$ ./mvnw spring-boot:build-image
```

Running `docker images` will allow you to see the built container

```
$ docker images
REPOSITORY                   TAG        IMAGE ID            CREATED             SIZE
localhost:5000/apps/shop     latest     db7876f3e0d1        40 years ago        279MB
```

### Putting the Image in a Registry

Up until this point the image only lives on your machine.
It is useful to instead place it in a registry so others can access and use that image.
[Docker Hub](https://hub.docker.com/) is a popular public registry but private registries exist as well.
In this lab you will be using a private registry on localhost.

### Running the Build and Pushing the Image

You should be able to run the Maven build and push the image to the local image registry.

```bash
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/shop
$ docker push localhost:5000/apps/shop
```

> NOTE: When you get an error like below you should run `docker system prune -a`.

> `[INFO]     [creator]     ERROR: failed to export: failed to write image to the following tags: [localhost:5000/apps/shop:latest: image load 'localhost:5000/apps/shop:latest'. first error: embedded daemon response: Error processing tar file(exit status 1): write /workspace/BOOT-INF/lib/aspectjweaver-1.9.6.jar: no space left on device]`

You can now see the image in the registry.

```bash
$ http GET localhost:5000/v2/_catalog
HTTP/1.1 200 OK
Content-Length: 43
Content-Type: application/json; charset=utf-8
Date: Mon, 31 Aug 2020 16:29:01 GMT
Docker-Distribution-Api-Version: registry/2.0
X-Content-Type-Options: nosniff

{
    "repositories": [
        "apps/shop"
    ]
}
```

> NOTE: You might see more repositories.
As long as the registry contains an "apps/shop" repository you're good to continue with the workshop.

### Deploying the Application on Kubernetes

Let's deploy our application.
First we need to create a `Deployment`:

```bash
$ kubectl create deployment shop --image localhost:5000/apps/shop
$ kubectl patch deployment shop --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/ports", "value":[{"containerPort":8080}]}]'
```

Then we need to expose our deployment so we can access our API:

```bash
$ kubectl expose deployment shop --name my-shop --port 80 --target-port 8080
```

When executing the previous command we only expose our API to everything running inside our Kubernetes cluster.

## Testing Our Application

To access our shop from outside the cluster and our lab environment we need to run:

```bash
$ kubectl port-forward services/my-shop 8080:80 --address 0.0.0.0
```

While this command is running you can visit `<public DNS>:8080/catalog/items` in another browser tab to verify you can access your running application.
Press `Control+C` to stop the port forwarding.