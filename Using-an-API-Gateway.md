# Using an API Gateway

## Table of Contents

* [Creating an API Gateway](#creating-an-api-gateway)
    * [Creating the API Gateway Application](#creating-the-api-gateway-application)
* [Defining Routes](#defining-routes)
* [Deploying Our API Gateway](#deploying-our-api-gateway)
    * [Enabling Additional Features](#enabling-additional-features)
    * [Deploying on Kubernetes](#deploying-on-kubernetes)
* [Testing Our API Gateway](#testing-our-api-gateway)

## Creating an API Gateway

Using this port forwarding trick we can easily access the running application.
However, the moment we want to add another functionality as a separate application we will not be able to use one IP address or DNS entry for two separate applications, or two Kubernetes services in this example.
In terms of functionality you could opt for a default Kubernetes `Ingress` which would allow you to route your traffic based on a (sub)path you want to access.
Unfortunately, the default Kubernetes `Ingress` doesn't support things like authentication, fail-over, rate limiting, and others.

This is where our next Spring Cloud project comes in: `Spring Cloud Gateway`.

Spring Cloud Gateway aims to provide a simple, yet effective way to route to APIs and provide cross cutting concerns to them such as: security, observability, and resiliency.

### Creating the API Gateway Application

In the Lab:

1. Run the following commands in your terminal (copy them verbatim to make the rest of the lab run smoothly):

```bash
$ mkdir -p ~/demo/gateway && cd ~/demo/gateway
$ curl https://start.spring.io/starter.tgz -d groupId=com.example.demo -d artifactId=gateway -d name=gateway -d description=Getting%20started%20with%20Spring%20Cloud%20-%20Gateway -d packageName=com.example.demo.gateway -d dependencies=actuator,cloud-gateway,cloud-starter-sleuth -d javaVersion=11 | tar -xzf -
```

2. Open the IDE using the “IDE” button at the top of the lab - it might be obscured by the “Call for Assistance” button.

Working on your own:

1. Click [here](https://start.spring.io/starter.ziptype=maven-project&language=java&platformVersion=2.3.3.RELEASE&packaging=jar&jvmVersion=11&groupId=com.example.demo&artifactId=gateway&name=gateway&description=Getting%20started%20with%20Spring%20Cloud%20-%20Gateway&packageName=com.example.demo.gateway&dependencies=actuator,cloud-gateway,cloud-starter-sleuth) to download a zip of the Spring Boot app
1. Unzip the project to your desired workspace and open in your favorite IDE

## Defining Routes

Now that we have our gateway application ready it is time to configure our route.
A route consists out of a predicate, potentially one or more filters, and a URI where our traffic will be routed to.

We'll route all traffic that uses the `/catalog` and `/orders` paths to our shop application which is accessible using the DNS of the Kubernetes service, `http://my-shop.default.svc.cluster.local`.

> NOTE: Remember that this DNS entry is only available to containers running inside your cluster.

We can configure our route either by using Java configuration, or by using an `application.yaml` file.

Adjust `GatewayApplication.java`:

```java
package com.example.demo.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class GatewayApplication {

	public static void main(String[] args) {
		SpringApplication.run(GatewayApplication.class, args);
	}

	@Bean
	public RouteLocator routes(RouteLocatorBuilder builder) {
		return builder.routes()
			.route("catalog_route",
				r -> r.path("/catalog/{*segment}")
				.uri("http://my-shop.default.svc.cluster.local")
			)
			.route("orders_route",
				r -> r.path("/orders/{*segment}")
				.uri("http://my-shop.default.svc.cluster.local")
			)
		.build();
	}

}
```

Or adjust `application.yaml`:
```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: catalog_route
        uri: http://my-shop.default.svc.cluster.local
        predicates:
        - Path=/catalog/{*segment}
      - id: orders_route
        uri: http://my-shop.default.svc.cluster.local
        predicates:
        - Path=/orders/{*segment}
```

## Deploying Our API Gateway

### Enabling Additional Features

Just like with our shop application we need to enable the graceful shutdown.
Add the following setting to you configuration:

```properties
server.shutdown=graceful
```

> NOTE: Do not forget to change the above configuration if you are using the YAML syntax.

### Deploying on Kubernetes

Just like with our shop application we will need to create an image, push the image to our local registry and deploy our application onto our Kubernetes cluster.
Since we already went over this before, you can use the following commands:

```bash
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/gateway
$ docker push localhost:5000/apps/gateway
$ kubectl create deployment gateway --image localhost:5000/apps/gateway
$ kubectl patch deployment gateway --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/ports", "value":[{"containerPort":8080}]}]'
$ kubectl expose deployment gateway --name my-gateway --port 80 --target-port 8080
```

## Testing Our API Gateway

To verify that our new routes are working as expected you can execute the command below and go to `<public DNS>:8080/catalog/items` in your browser.

```bash
$ kubectl port-forward services/my-gateway 8080:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

Execute the next command to check if our `orders` route is working as expected.

```bash
$ http POST localhost:8080/orders Content-Type:application/json
HTTP/1.1 201 Created
Content-Length: 0
Date: Mon, 31 Aug 2020 18:10:27 GMT
Location: /orders/da5f1b18-d3ed-4f3d-851d-a163605f0353
```

This command will allow us to access our application without attaching the terminal.
If you want to stop the port forwarding you can do so with the following command:

```bash
$ pkill kubectl -9
```