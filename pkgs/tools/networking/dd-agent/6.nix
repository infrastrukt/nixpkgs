{ stdenv, fetchFromGitHub, buildGoPackage, makeWrapper, pythonPackages, pkgconfig, systemd }:

let
  # keep this in sync with github.com/DataDog/agent-payload dependency
  payloadVersion = "4.7.1";

in buildGoPackage rec {
  name = "datadog-agent-${version}";
  version = "6.4.2";
  owner   = "DataDog";
  repo    = "datadog-agent";

  src = fetchFromGitHub {
    inherit owner repo;
    rev    = "155fddb3547919bd54530dfdb250e0cb2defae7d";
    sha256 = "0l7ic0p2h27x386k1gzzm20af2s06cpalmqz0h0c5zq4wszmw5zy";
  };

  subPackages = [
    "cmd/agent"
    "cmd/dogstatsd"
    "cmd/py-launcher"
    # Does not compile: go/src/github.com/DataDog/datadog-agent/cmd/cluster-agent/main.go:31:12: undefined: app.ClusterAgentCmd
    #"cmd/cluster-agent"
  ];
  goDeps = ./deps.nix;
  goPackagePath = "github.com/${owner}/${repo}";

  # Explicitly set this here to allow it to be overridden.
  python = pythonPackages.python;

  nativeBuildInputs = [ pkgconfig makeWrapper ];
  buildInputs = [ systemd ];
  PKG_CONFIG_PATH = "${python}/lib/pkgconfig";


  preBuild = let
    ldFlags = stdenv.lib.concatStringsSep " " [
      "-X ${goPackagePath}/pkg/version.Commit=${src.rev}"
      "-X ${goPackagePath}/pkg/version.AgentVersion=${version}"
      "-X ${goPackagePath}/pkg/serializer.AgentPayloadVersion=${payloadVersion}"
      "-X ${goPackagePath}/pkg/collector/py.pythonHome=${python}"
      "-r ${python}/lib"
    ];
  in ''
    buildFlagsArray=( "-tags" "ec2 systemd cpython process log" "-ldflags" "${ldFlags}")
  '';

  # DataDog use paths relative to the agent binary, so fix these.
  postPatch = ''
    sed -e "s|PyChecksPath =.*|PyChecksPath = \"$bin/${python.sitePackages}\"|" \
        -e "s|distPath =.*|distPath = \"$bin/share/datadog-agent\"|" \
        -i cmd/agent/common/common_nix.go
  '';

  # Install the config files and python modules from the "dist" dir
  # into standard paths.
  postInstall = ''
    mkdir -p $bin/${python.sitePackages} $bin/share/datadog-agent
    cp -R $src/cmd/agent/dist/{conf.d,trace-agent.conf} $bin/share/datadog-agent
    cp -R $src/cmd/agent/dist/{checks,utils,config.py} $bin/${python.sitePackages}

    cp -R $src/pkg/status/dist/templates $bin/share/datadog-agent

    wrapProgram "$bin/bin/agent" \
        --set PYTHONPATH "$bin/${python.sitePackages}"
  '';

  meta = with stdenv.lib; {
    description = ''
      Event collector for the DataDog analysis service
      -- v6 new golang implementation.
    '';
    homepage    = https://www.datadoghq.com;
    license     = licenses.bsd3;
    platforms   = platforms.all;
    maintainers = with maintainers; [ thoughtpolice domenkozar rvl ];
  };
}
