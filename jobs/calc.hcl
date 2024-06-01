
job "calc-job" {
  datacenters = ["nomad1"]
  type = "batch"

  group "calc-group" {
    task "calc-task" {
      driver = "raw_exec"

      config {
        command = "cmd"
        args = ["/c", "calc.exe"]
      }

      resources {
        cpu = 500
        memory = 256
      }
    }
  }
}

