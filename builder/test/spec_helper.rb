require 'serverspec'
set :backend, :exec

def image_path
  "alpineos-rpi-#{ENV['VERSION']}.img.zip"
end
