{ lib }:
let
  domain = "risse.tv";
  prefix = "192.168.73";
  gateway = "${prefix}.1";
  subnet = "${prefix}.0/24";
  reverseZone =
    let parts = lib.splitString "." prefix;
    in lib.concatStringsSep "." (lib.reverseList parts) + ".in-addr.arpa";

  hosts = {
    galleta = { ip = "192.168.73.1"; mac = "00:0e:c4:ce:d9:6e"; cnames = [ "router" ]; };
    pi3 = { ip = "192.168.73.2"; mac = "b8:27:eb:86:1f:26"; };
    pi4 = { ip = "192.168.73.3"; mac = "dc:a6:32:1d:f3:50"; };
    qube = { ip = "192.168.73.4"; mac = "8e:e4:dc:57:ed:0a"; cnames = [ "mrtg" "whatsup" "wasgeht" "grafana" ]; };
    switch1 = { ip = "192.168.73.5"; mac = "ec:9a:74:0f:b8:80"; cnames = [ "switch2" ]; };
    ap1 = { ip = "192.168.73.6"; mac = "20:05:b6:ff:d4:d0"; };
    ap2 = { ip = "192.168.73.7"; mac = "20:05:b6:ff:d1:40"; };
    solar = { ip = "192.168.73.8"; mac = "84:d6:c5:74:d1:d4"; };
    corner = { ip = "192.168.73.9"; mac = "52:54:00:b0:82:e7"; };
    watson = { ip = "192.168.73.11"; mac = "f6:8c:de:0f:88:f7"; };
    zugzug = { ip = "192.168.73.12"; mac = "be:5b:10:d8:43:71"; };
    area76 = { ip = "192.168.73.13"; mac = "28:7f:cf:94:ed:73"; };
    dev-router = { ip = "192.168.73.31"; mac = "52:54:00:bf:23:21"; };
    k8s-master = { ip = "192.168.73.51"; mac = "52:54:00:78:bf:06"; };
    k8s-worker1 = { ip = "192.168.73.52"; mac = "52:54:00:a1:e1:77"; };
    k8s-worker2 = { ip = "192.168.73.53"; mac = "52:54:00:4e:6b:e4"; };
    db = { ip = "192.168.73.54"; mac = "52:54:00:17:0d:75"; };
    lab-master = { ip = "192.168.73.55"; mac = "52:54:00:aa:3e:20"; };
    lab-worker1 = { ip = "192.168.73.56"; mac = "52:54:00:ea:db:21"; };
    lab-worker2 = { ip = "192.168.73.57"; mac = "52:54:00:80:f9:01"; };
    htb = { ip = "192.168.73.61"; mac = "52:54:00:54:52:fc"; };
    gibson = { ip = "162.243.69.6"; };
  };

  forwardARecords =
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: h: "${name}  IN  A  ${h.ip}") hosts
    );

  cnameRecords =
    lib.concatStringsSep "\n" (lib.concatLists (
      lib.mapAttrsToList
        (name: h:
          map (alias: "${alias}  IN  CNAME  ${name}.${domain}.")
            (h.cnames or [ ])
        )
        hosts
    ));

  reversePtrRecords =
    let
      matching = lib.filterAttrs (_: h: lib.hasPrefix "${prefix}." h.ip) hosts;
      entries = builtins.sort (a: b: a.octet < b.octet) (
        lib.mapAttrsToList
          (name: h: {
            inherit name;
            octet = lib.strings.toInt (lib.last (lib.splitString "." h.ip));
          })
          matching
      );
    in
    lib.concatStringsSep "\n" (
      map (e: "${toString e.octet}  IN  PTR  ${e.name}.${domain}.") entries
    );

  dhcpReservations =
    lib.mapAttrsToList
      (name: h: {
        hostname = name;
        hw-address = h.mac;
        ip-address = h.ip;
      })
      (lib.filterAttrs (_: h: h ? mac) hosts);

in
{
  inherit domain prefix gateway subnet reverseZone hosts;
  inherit forwardARecords cnameRecords reversePtrRecords dhcpReservations;
}
