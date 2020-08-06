# Getting started with Spring Cloud
Workshop Materials: https://github.com/TYsewyn/Getting-started-with-Spring-Cloud

Tim Ysewyn, Solutions Architect, VMware

## What You Will Do

- Define a contract between two applications
- Create a basic Spring Boot application
- Deploy and run the application on Kubernetes
- Configure an API gateway
- Make your application more resilient

## Prerequisites
Everyone will need:

- Basic knowledge of Spring and Kubernetes (we will not be giving an introduction to either)

If you are following these notes from an event, all the pre-requisites will be provided in the Lab. You only need to worry about these if you are going to work through the lab on your own.

- [JDK 8 or higher](https://openjdk.java.net/install/index.html) installed. **Ensure you have a JDK installed and not just a JRE**
- [Docker](https://docs.docker.com/install/) installed.
- [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed.
- [HTTPie](https://httpie.org/) installed.
- [Spring Boot CLI](https://docs.spring.io/spring-boot/docs/current/reference/html/getting-started.html#getting-started-installing-the-cli) and [Spring Cloud CLI](https://cloud.spring.io/spring-cloud-cli/reference/html/#_installation) installed.

### Doing the Workshop on Your Own

- If you are doing this workshop on your own, you will need to have your own Kubernetes cluster and Docker repo that the cluster can access:
    - **Docker Desktop and Docker Hub** - Docker Desktop lets you easily setup a local Kubernetes cluster ([Mac](https://docs.docker.com/docker-for-mac/#kubernetes), [Windows](https://docs.docker.com/docker-for-windows/#kubernetes)).
    This, in combination with [Docker Hub](https://hub.docker.com/), should let you run through this workshop.
    - **Hosted Kubernetes Clusters and Repos** - Various cloud providers, such as Google and Amazon, offer options for running Kubernetes clusters and repositories in the cloud.
    You will need to follow instructions from the cloud provider to provision the cluster and repository as well as for configuring `kubectl` to work with the cluster.

### Doing The Workshop in Strigo

1. Login To Strigo.

1. Configure `git`. Run this command in the terminal:

```bash
$ git config --global user.name "<name>"
$ git config --global user.email "<email>"
```

3. To configure `kubectl`, run the following command in the terminal:

```bash
$ kind-setup
Cluster already active: kind
Setting up kubeconfig
```

4. Verify `kubectl` is configured correctly

```bash
$ kubectl cluster-info
Kubernetes master is running at https://127.0.0.1:43723
KubeDNS is running at https://127.0.0.1:43723/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

To further debug and diagnose cluster problems, use `'kubectl cluster-info dump'`.

> NOTE: It might take a minute or so after the VM launches to get the Kubernetes API server up and running, so your first few attempts at using kubectl may be very slow or fail.
After that it should be responsive.

5. Install `tree`

```bash
$ nix-env -i tree
```

### Setting up the environment

1. Installing Kubernetes [Operator Lifecycle Manager](https://github.com/operator-framework/operator-lifecycle-manager)

    `curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/0.15.1/install.sh | bash -s 0.15.1`
    
        NOTE: Check [the OLM releases](https://github.com/operator-framework/operator-lifecycle-manager/releases) to install the latest version.

2. Redis Operator (assuming your K8s cluster has internet access)

    `kubectl create -f https://raw.githubusercontent.com/TYsewyn/Getting-started-with-Spring-Cloud/master/redis-operator.yaml`

3. Redis

    `kubectl create -f https://raw.githubusercontent.com/TYsewyn/Getting-started-with-Spring-Cloud/master/redis.yaml`

## Table of Workshop Contents

* [Our Product](Our-Product.md)
    * [Defining and Creating the Contracts](Our-Product.md#defining-and-creating-the-contracts)
    * [Mocking the API](Our-Product.md#mocking-the-api)
    * [Implementing the API](Our-Product.md#implementing-the-api)
        * [Configuring Our Contract Tests](Our-Product.md#configuring-our-contract-tests)
        * [Implementing and Verifying our API](Our-Product.md#implementing-and-verifying-our-api)
    * [Deploying Our Application](Our-Product.md#deploying-our-application)
        * [Enabling Additional Features](Our-Product.md#enabling-additional-features)
        * [Building an Image](Our-Product.md#building-an-image)
        * [Putting the Image in a Registry](Our-Product.md#putting-the-image-in-a-registry)
        * [Running the Build and Pushing the Image](Our-Product.md#running-the-build-and-pushing-the-image)
        * [Deploying the Application on Kubernetes](Our-Product.md#deploying-the-application-on-kubernetes)
    * [Testing Our Application](Our-Product.md#testing-our-application)
* [Using an API Gateway](Using-an-API-Gateway.md)
    * [Creating an API Gateway](Using-an-API-Gateway.md#creating-an-api-gateway)
        * [Creating the API Gateway Application](Using-an-API-Gateway.md#creating-the-api-gateway-application)
    * [Defining Routes](Using-an-API-Gateway.md#defining-routes)
    * [Deploying Our API Gateway](Using-an-API-Gateway.md#deploying-our-api-gateway)
        * [Enabling Additional Features](Using-an-API-Gateway.md#enabling-additional-features)
        * [Deploying on Kubernetes](Using-an-API-Gateway.md#deploying-on-kubernetes)
    * [Testing Our API Gateway](Using-an-API-Gateway.md#testing-our-api-gateway)
* [Making Your Application More Resilient](Making-Your-Application-More-Resilient.md)
    * [Scaling Your Application](Making-Your-Application-More-Resilient.md#scaling-your-application)
    * [Load Balancing Your Upstream Traffic](Making-Your-Application-More-Resilient.md#load-balancing-your-upstream-traffic)
        * [Configuring Our Shop Application](Making-Your-Application-More-Resilient.md#configuring-our-shop-application)
        * [Adding New Dependencies to Our Gateway](Making-Your-Application-More-Resilient.md#adding-new-dependencies-to-our-gateway)
        * [Configuring Security Inside Kubernetes](Making-Your-Application-More-Resilient.md#configuring-security-inside-kubernetes)
        * [Configuring Our Load Balancer](Making-Your-Application-More-Resilient.md#configuring-our-load-balancer)
        * [Adapting Our Route](Making-Your-Application-More-Resilient.md#adapting-our-route)
        * [Deploying Our New Gateway](Making-Your-Application-More-Resilient.md#deploying-our-new-gateway)
        * [Testing Our Route to an Unhealthy Instance](Making-Your-Application-More-Resilient.md#testing-our-route-to-an-unhealthy-instance)
    * [Respond Fast](Making-Your-Application-More-Resilient.md#respond-fast)
        * [Configuring Our Shop Application](Making-Your-Application-More-Resilient.md#configuring-our-shop-application-1)
        * [Testing Our Delay](Making-Your-Application-More-Resilient.md#testing-our-delay)
        * [Adapting Our Route](Making-Your-Application-More-Resilient.md#adapting-our-route-1)
        * [Deploying Our New Gateway](Making-Your-Application-More-Resilient.md#deploying-our-new-gateway-1)
        * [Testing Our Route](Making-Your-Application-More-Resilient.md#testing-our-route)
    * [Rerouting Failing Traffic - Retry](Making-Your-Application-More-Resilient.md#rerouting-failing-traffic---retry)
        * [Adapting Our Route](Making-Your-Application-More-Resilient.md#adapting-our-route-2)
        * [Deploying Our New Gateway](Making-Your-Application-More-Resilient.md#deploying-our-new-gateway-2)
        * [Testing Our Route](Making-Your-Application-More-Resilient.md#testing-our-route-1)
    * [Rerouting Failing Traffic - Circuit Breaker or Fallback](Making-Your-Application-More-Resilient.md#rerouting-failing-traffic---circuit-breaker-or-fallback)
        * [Configuring Our Shop Application](Making-Your-Application-More-Resilient.md#configuring-our-shop-application-2)
        * [Deploying Our New Shop](Making-Your-Application-More-Resilient.md#deploying-our-new-shop)
        * [Testing Our Failing Shop](Making-Your-Application-More-Resilient.md#testing-our-failing-shop)
        * [Adding Missing Dependencies](Making-Your-Application-More-Resilient.md#adding-missing-dependencies)
        * [Adding Our New Load Balancer](Making-Your-Application-More-Resilient.md#adding-our-new-load-balancer)
        * [Adapting Our Route](Making-Your-Application-More-Resilient.md#adapting-our-route-3)
        * [Deploying Our New Gateway](Making-Your-Application-More-Resilient.md#deploying-our-new-gateway-3)
        * [Testing Our Route](Making-Your-Application-More-Resilient.md#testing-our-route-2)
    * [Rate Limiting Incoming Traffic](Making-Your-Application-More-Resilient.md#rate-limiting-incoming-traffic)
        * [Adding Missing Dependencies](Making-Your-Application-More-Resilient.md#adding-missing-dependencies-1)
        * [Configuring Our Redis Connection](Making-Your-Application-More-Resilient.md#configuring-our-redis-connection)
        * [Configuring Our Route](Making-Your-Application-More-Resilient.md#configuring-our-route)
        * [Testing Our Route](Making-Your-Application-More-Resilient.md#testing-our-route-3)
* [Follow-up resources](Follow-Up-Resources.md)