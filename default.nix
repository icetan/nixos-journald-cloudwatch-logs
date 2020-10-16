{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.services.journald-cloudwatch-logs;
  config-file = pkgs.writeText "journald-cloudwatch-logs" ''
    log_group = "${cfg.log_group}"
    state_file = "${cfg.state_file}"
    ${cfg.extraConfig}
  '';
  journald-cloudwatch-logs = pkgs.callPackage ./journald-cloudwatch-logs.nix {};

  name = "journald-cloudwatch-logs";
  home = "/var/lib/journald-cloudwatch-logs";
in {
  options.services.journald-cloudwatch-logs = {
    enable = mkEnableOption "journald-cloudwatch-logs";

    log_group = mkOption {
      type = types.str;
      description = ''
        (Required) The name of the cloudwatch log group to write logs
        into. This log group must be created before running the program.
      '';
    };

    state_file = mkOption {
      type = types.str;
      description = ''
        Path to a location where the program can write,
        and later read, some state it needs to preserve between runs. (The format
        of this file is an implementation detail.)
      '';
      default = "${home}/state";
    };

    aws_access_key_id = mkOption {
      type = types.str;
      description = ''
        AWS access key ID
      '';
    };

    aws_secret_access_key = mkOption {
      type = types.str;
      description = ''
        AWS secret access key
      '';
    };

    extraConfig = mkOption {
      type = types.str;
      description = ''
        ec2_instance_id: (Optional) The id of the EC2 instance on which the tool
        is running. There is very little reason to set this, since it will be
        automatically set to the id of the host EC2 instance.

        journal_dir: (Optional) Override the directory where the systemd journal
        can be found. This is useful in conjunction with remote log aggregation,
        to work with journals synced from other systems. The default is to use the
        local system's journal.

        log_priority: (Optional) The highest priority of the log messages to read
        (on a 0-7 scale). This defaults to DEBUG (all messages). This has a behaviour
        similar to journalctl -p <priority>. At the moment, only a single value
        can be specified, not a range. Possible values are: 0,1,2,3,4,5,6,7 or one
        of the corresponding "emerg", "alert", "crit", "err", "warning", "notice",
        "info", "debug". When a single log level is specified, all messages with
        this log level or a lower (hence more important) log level are read and
        pushed to CloudWatch. For more information about priority levels, look at
        https://www.freedesktop.org/software/systemd/man/journalctl.html

        log_stream: (Optional) The name of the cloudwatch log stream to write logs
        into. This defaults to the EC2 instance id. Each running instance of this
        application (along with any other applications writing logs into the same log
        group) must have a unique log_stream value. If the given log stream doesn't
        exist then it will be created before writing the first set of journal events.

        buffer_size: (Optional) The size of the local event buffer where journal
        events will be kept in order to write batches of events to the CloudWatch
        Logs API. The default is 100. A batch of new events will be written to
        CloudWatch Logs every second even if the buffer does not fill, but this
        setting provides a maximum batch size to use when clearing a large backlog
        of events, e.g. from system boot when the program starts for the first time.

        aws_region: (Optional) The AWS region whose CloudWatch Logs API will be
        written to. If not provided, this defaults to the region where the host EC2
        instance is running.
      '';
      default = "";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.journald-cloudwatch-logs = {
      enable = true;

      description = "journald-cloudwatch-logs";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        AWS_ACCESS_KEY_ID = cfg.aws_access_key_id;
        AWS_SECRET_ACCESS_KEY = cfg.aws_secret_access_key;
      };

      serviceConfig = {
        User = name;
        Group = name;
        ExecStart = "${journald-cloudwatch-logs}/bin/journald-cloudwatch-logs ${config-file}";
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = 42;
      };

      preStart = ''
        mkdir -p "$(dirname "${cfg.state_file}")"
        rm -rf "${cfg.state_file}"
      '';
    };

    users.extraUsers = {
      "${name}" = {
        name = name;
        group = name;
        extraGroups = [ "systemd-journal" ];
        home = home;
        createHome = true;
        shell = "${pkgs.bash}/bin/bash";
        isSystemUser = true;
      };
    };

    users.extraGroups = {
      "${name}" = { name = name; };
    };
  };
}
