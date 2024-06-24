# HelixML Local Development guide

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Setting Up the Development Environment](#setting-up-the-development-environment)
4. [Project Structure](#project-structure)
5. [Running the Application](#running-the-application)
6. [Debugging](#debugging)
7. [Contributing](#contributing)
8. [Further Reading](#further-reading)

## Introduction

Welcome to the local development documentation for **Helix.ml**! This guide will help you set up your development environment, understand the project structure, run the application locally, and contribute to the Helix.

## Prerequisites

Before you start, ensure you have the following software installed on your machine:

- **docker**
- **golang**
- **Node.js** and **npm**

## Setting Up the Development Environment

1. **Clone the Repository**

   ```bash
   git clone git@github.com:helixml/helix.git
   cd helix
   ```

    If you are an external contributor, consider working out of a forked repository of Helix.

2. **Set Up Environment Variables**

    Create an `.env` file with settings based on the example values and edit it:

    ```
    cp .env.example-prod .env
    ```

    The default values for settings are optimised for local development.


## Project Structure

Here is an overview of the project structure:

```
helix/
├── Dockerfiles         # Dockerfiles for various environments
├── api/                # Main Control Plane API directory
│   ├── cmd/            # Standard golang project structure within here
│   ├── pkg/            #
│   ├── main.go         #
├── llamaindex/         # llamaindex
│   └── src/            #
│   └── ...             # Other app-specific files
├── unstructured        # Python Unstructured for parsing content
├── scripts             # Scripts to get stuff done
├── runner              # Runner configurations
├── frontend/           # Frontend in React, ts
│   ├── package.json    # npm dependencies
│   └── src/            # Source files for the frontend
└── .env                # Environment variables file
```

## Running the Application

1. **Bring up the Helix stack**

   ```bash
   ./stack up
   ```
    This will bring up the control plane which serves the front-end and various other components on the stack. Refer Helix architecture [docs] (https://docs.helix.ml/helix/getting-started/architecture/)

    The control comes up on http://localhost:8080 by default.

    Sanity check your environment with

    ```
    docker ps
    ```

    This should show you the running containers

    ```
    $ docker ps
    IMAGE                                       PORTS                                       NAMES
    ankane/pgvector                             0.0.0.0:5433->5432/tcp, :::5433->5432/tcp   helix-pgvector-1
    helix-frontend                              0.0.0.0:8081->8081/tcp, :::8081->8081/tcp   helix-frontend-1
    helix-gptscript_runner                                                                  helix-gptscript_runner-1
    registry.helix.ml/helix/llamaindex:latest                                               helix-llamaindex-1
    webhookrelay/webhookrelayd                                                              helix-webhook_relay_github-1
    webhookrelay/webhookrelayd                                                              helix-webhook_relay_stripe-1
    helix-api                                   0.0.0.0:8080->80/tcp, :::8080->80/tcp       helix-api-1
    postgres:12.13-alpine                       0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   helix-postgres-1
    quay.io/keycloak/keycloak:23.0              8080/tcp, 8443/tcp                          helix-keycloak-1
    ```
2. **Attach a runner**

    Follow the [instructions on the docs to attach a runner](https://docs.helix.ml/helix/private-deployment/controlplane/#attaching-a-runner)

3. **Rebuild individual components**

    ```
    ./stack rebuild <component>
    ```

    If you're familiar with [tmux](https://github.com/tmux/tmux/wiki) you will find it useful to do `./stack start` and `./stack stop` instead.

    Build individual components with the following commands

    - Build the api with
        ```
        go mod download
        go build -o helix
        ```

4. **Tear down the Helix stack**

    Bring down the stack

    ```
    ./stack stop
    ```


## Debugging

- **View all Docker logs**

    ```
    docker logs <container-name>
    ```
## Contributing

1. **Branching Strategy**

   - Create a new branch for each feature or bugfix:

     ```bash
     git checkout -b feature/your-feature-name
     ```

2. **Code Style**

   - Format all code with standard language formatters.
   - Follow the project's coding guidelines for the frontend.

3. **Commit Messages**

   - Write clear and concise commit messages.

4. **Pull Requests**

   - Submit a pull request to the `main` branch for review.


## Further Reading

- [Helix Documentation](https://docs.helix.ml/)

Happy coding! If you have any questions or run into issues, feel free to reach out to the maintainers on [👥 Discord](https://discord.gg/VJftd844GE).