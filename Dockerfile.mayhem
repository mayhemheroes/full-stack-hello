FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential python

ADD . /full-stack-hello
WORKDIR /full-stack-hello
RUN make

RUN mkdir -p /deps
RUN ldd /full-stack-hello/as_exec | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /full-stack-hello/as_exec /full-stack-hello/as_exec
ENV LD_LIBRARY_PATH=/deps
