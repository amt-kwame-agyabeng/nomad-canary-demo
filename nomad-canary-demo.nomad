job "nomad-canary-demo" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 1

    update {
      max_parallel      = 1
      canary            = 1
      auto_promote      = true
      auto_revert       = true
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "2m"
      progress_deadline = "5m"
    }

    network {
      mode = "host"

      port "http" {
        to = 5000
      }
    }

    service {
      name     = "nomad-canary-demo"
      provider = "consul"
      port     = "http"

      check {
        name     = "application-health"
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:bf8589af0b8238bdf2f530db0723cb71bf70ff39"
        ports = ["http"]
      }



      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
