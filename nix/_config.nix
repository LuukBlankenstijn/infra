{
  domain = "luukblankenstijn.nl";
  kanidmHost = "id.luukblankenstijn.nl";
  netbirdHost = "netbird.luukblankenstijn.nl";

  cloudflareZone = "luukblankenstijn.nl";
  adminEmail = "acme@luukblankenstijn.nl";
  timeZone = "Europe/Amsterdam";

  adminUser = {
    name = "luuk";
    displayName = "Luuk Blankenstijn";
    legalName = "Luuk Blankenstijn";
    mailAddresses = [ "me@luukblankenstijn.nl" ];
  };

  rootAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnm7ME9L/KuEGbSbzPJ4uVgsNl579UCCtXAIlWNYq7x"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMarYoGEgRvnizveVM8OK9FVLlrV/rlY0OScqrKpazuG"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICIyWVxyi8sP49x/kIzobI6f/IJrlbXMQ8l/UuSKLryC"
  ];
}
