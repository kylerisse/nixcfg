{
  image = "ghcr.io/open-webui/open-webui:ollama";

  environment = {
    "TZ" = "America/Los_Angeles";
    "USER_AGENT" = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36";
  };

  volumes = [
    "/home/open-webui/ollama:/root/.ollama/"
    "/home/open-webui/data:/app/backend/data"
    "/home/open-webui/rag-docs:/data/docs"
  ];

  ports = [
    "127.0.0.1:3000:8080" # Ensures we listen only on localhost
  ];

  extraOptions = [
    "--pull=newer" # Pull if the image on the registry is newer
    "--name=open-webui"
    "--hostname=open-webui"
    "--network=host"
    "--add-host=host.containers.internal:host-gateway"
  ];
}
