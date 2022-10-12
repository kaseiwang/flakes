{ config, pkgs, ... }:
let
  tincName = "kaseinet";
in {
  services.tinc.networks."${tincName}"= {
    package = pkgs.tinc;
    hostSettings = {
      netease_office = {
        subnets = [ { address = "10.10.0.102/32"; } ];
        rsaPublicKey = ''
        -----BEGIN RSA PUBLIC KEY-----
        MIIBCgKCAQEA/IkctX2iNtbfCBjLFRGfNYDlHjl2MxDDS+kQqD3RkzHznpSwtz7O
        kuLXs0VCPtAW7jI9N15VyiBFElrDUO43ocFp6j/K1PsgJA3cCJaPcfDvppN4byxs
        KOev3U+3QyP1HXrhnbKAEBOCqyG/xltEDFxU4gbDJrTMubmw9rFkONNhaeHFEUOa
        pKE7ImB2jPKbFWLKpYF91QZXywQ5epKEKC8W4wBctKHjqh+XN5U6+kSaUgVYTcZj
        S0fXKNAfs2U3etBf89ceh2PByjGHAselsieJCCIG+IxMXZ5w5/zpTnpJAklXj05Q
        YdL/8Kf0En+F801ZXy2GR664eqR9Zl8hYQIDAQAB
        -----END RSA PUBLIC KEY-----
        '';
      };
      n3160 = {
        subnets = [
          { address = "10.10.0.6/32"; }
          { address = "10.10.2.0/24"; }
        ];
        rsaPublicKey = ''
        -----BEGIN RSA PUBLIC KEY-----
        MIIBCgKCAQEAsulmcHlajLgf0rAm85Z36kRtSvV3jUD2r0yUOdlWQZ2te/okW71l
        GmZI1RyAH7ueSA6RwQass21biVjl5LKRl6pCzJulYHyoo2BYvilYWnBqU7Qt7onc
        5SbRGY2TI/o0qskQJS0EH4jkNhT008r9iJo0wrN8G3sfrGs+JjA3m9zl5wSdE8mR
        hjLEvjhT7GW7qujq5ml+VTPctizgaZlcp/hbo2v9JURdoqatfAzc7X0tUybnsIZA
        KRo+VfAlw9Kxr78meQdfrYoG+PpgdANhoWuzJVfEh0Kkpm824Kydihw3u0/bBiBj
        Rsskvv18GFRSIxadjqMXvuhUdpmMGjNtVwIDAQAB
        -----END RSA PUBLIC KEY-----'';
      };
      c940 = {
        subnets = [ { address = "10.10.0.110/32"; } ];
        rsaPublicKey = ''
        -----BEGIN RSA PUBLIC KEY-----
        MIIBCgKCAQEA4vg07BxHnUPF9JK0F1Vo/xZaDU75lmBvnX/CDdvjIWPbkVhbHDIk
        ecJ5XPKGWYrzDmvLLTPXHgBuLn002NqaizZF3kOIvyUVlNea/wf1FXAunoZ0be1d
        PacwbmcETPppSnOr7ApsRZeM+Rxpx1MsIrX2cdzxxnJgHvzNU+L8NIihGVUD6QYE
        7ZmXyWmFHP+6le2ZGNCewGsm0W3FgZ5Vh1ph8ynoUtlEBofz6QyFscEvE2J1J2vB
        hced0rrec77XpFspSBUEnOSOQ7kLZyxIFOcin2aA1WhYs6pP3CAfLOW8UbjWdlQK
        KJu1llyNwQoUWJrO/EtH8fI9fHAa0cJhXQIDAQAB
        -----END RSA PUBLIC KEY-----'';
      };
      rfc = {
        addresses = [
          { address = "103.200.112.206"; }
        ];
        subnets = [
          { address = "10.10.0.10/32"; }
        ];
        rsaPublicKey = ''
        -----BEGIN RSA PUBLIC KEY-----
        MIICCgKCAgEAq7IewT+s/B3ygISXzYHMBsAOBCxvRVtma+Fn9hKYHZ6aBf0DJWPJ
        WohlUOsbrkxQK+thH+CiDuUxDm9UXA1rpBrhypv3c4UgV0jVGAK5rJl1x0Mt+eXQ
        HE6LBSEESQUF6H0TmYrx/g/8T0WItVYFHowxWZmmVoyso/at+kbkpomUK7DjWCCD
        Sg/+6qWs9xcoqINGC8dPsXS5/3N/BewIMsAwftW3s/NHIsByry+pV8qNAfF4FoQH
        +Bx0lplZOQgy0viCcW6OVU/Ra7/QnrxPEesJzYM9r0ONKDo5Q6lxeZFZIvnFdDQ9
        UBvpMzeWLBpmsaMe03MP3OQjkKH1SJ8x7pGcMMw+1e1g7HvLEK9fB+47CxIOysR+
        9Q6xBIrZOTMG2xz/ow4KRe8Q6q53kuOCpreez7/qNBIIuH9LT8G6YjysM0KpseyN
        Pp3YeD6k01dybdfHTGd5EM61ElNt0vxi4kG7kJ9WSTBRfgAbs3K+ZBLf/P8n7K3Z
        W4ex6uFhj1aRdlRhjQo18fVHBEkzFpYpt49Ap6GcTzWgXtCRrGz6NyyWse67/cIn
        bdS0vyKn9ZhPgxmY4wzpoeo8ZN0ColK60+JzaFs2/6P1UTyGjs/wiqBUB/QP49fe
        c4zc0/oqqeQcZuCkGGNnBGKaR7DJTFv672A+0MThbFkMzyxvAFc0dVcCAwEAAQ==
        -----END RSA PUBLIC KEY-----'';
      };
      gz1 = {
        addresses = [
          { address = "81.71.146.69"; }
        ];
        subnets = [
          { address = "10.10.0.11/32"; }
        ];
        rsaPublicKey = ''
        -----BEGIN RSA PUBLIC KEY-----
        MIIBCgKCAQEA1qOsh6DeJfX0JXptA/5BaL1Hso7qXJ6uGVjG2hgNRZZLNLn1orZR
        muuUqjhwqtoYdc/EyEtvQ6Ay6WLN3E5AwszoqYmgNDEyYMZtlKpozfUVoK3BwyVJ
        Rmra7eE+JJcJsvQwxT1rhIF28uyEPMRvLcFhZytalBCIWTR17+3yxB5GBxOeOT15
        Kw47qbR1zZrrCdYnMqVcsY/zVgr8IOdkq2ESjzKMLDitgbrE9H1A3F5zab7LgRUB
        6qDTzSP0/PAFf0vzilYyfTc6NWd5RVt0L7hI501hgrT33+rhr0TG8h42TIoC/D/L
        0OB53j1kCGSS5jCCRVLWiBTmGM1qrFdSDwIDAQAB
        -----END RSA PUBLIC KEY-----'';
      };
    };
  };

  networking.interfaces."tinc.${tincName}" = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "10.10.0.11";
      prefixLength = 32;
    }];
    ipv4.routes = [
      { address = "10.10.0.0"; prefixLength = 24; }
      { address = "10.10.2.0"; prefixLength = 24; }
    ];
  };
}