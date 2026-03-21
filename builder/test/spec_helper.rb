require 'serverspec'
set :backend, :exec

def image_path
  if ENV['ALPINE_ARCH'] == 'aarch64'
    "alpineos-rpi-arm64-#{ENV['VERSION']}.img.zip"
  else
    "alpineos-rpi-#{ENV['VERSION']}.img.zip"
  end
end
