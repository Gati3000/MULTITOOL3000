FROM debian:12-slim
ARG Branch=Main
ARG Url=https://github.com/Gati3000/Gere-Lab.git
ARG Stamp=0
RUN apt-get update -qq && apt-get install -y -qq git python3 ca-certificates && rm -rf /var/lib/apt/lists/*
RUN echo "$Stamp" >/dev/null && git clone --quiet --branch "$Branch" "$Url" /opt/Gere-Lab
WORKDIR /opt/Gere-Lab
RUN python3 App/Maintenance/Update.py && rm -rf /var/lib/apt/lists/*
RUN mkdir -p Database/Messeges Database/Parts
EXPOSE 8080 8081
CMD [".venv/bin/python", "Main.py"]
