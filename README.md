# picat

Hello, picat is a simple tool for populating template files.

## about

While working on a recent project, I wanted a way to create generic template files that could be filled with specific data.

I was too lazy to find one online, so I'm creating this for my very specific and narrow use case. It was also a good opportunity to learn a new language.

## usage

_compose.template:_

```yml
services:
  app:
    image: <<image_name>>
    container_name: app
    ports:
      - <<port>>:80
    env_file:
      - ~/.env
```

_command:_

`picat --in=compose.template --out=compose.yml --values='{"image_name":"amazing-app:latest", "port":8080}'`
