{
  source,
  lib,
  buildPythonPackage,
  hatchling,
  android-backup,
  attrs,
  click,
  construct,
  crcmod,
  croniter,
  cryptography,
  defusedxml,
  micloud,
  netifaces,
  platformdirs,
  pydantic,
  pyyaml,
  tqdm,
  zeroconf,
  pytest-asyncio,
  pytest-mock,
  pytestCheckHook,
}:

buildPythonPackage {
  inherit (source) pname src;
  version = "0.6.0.dev0-unstable-${source.date}";
  pyproject = true;

  build-system = [ hatchling ];

  dependencies = [
    android-backup
    attrs
    click
    construct
    crcmod
    croniter
    cryptography
    defusedxml
    micloud
    netifaces
    platformdirs
    pydantic
    pyyaml
    tqdm
    zeroconf
  ];

  nativeCheckInputs = [
    pytest-asyncio
    pytest-mock
    pytestCheckHook
  ];

  pythonImportsCheck = [
    "miio"
    "miio.cli"
    "miio.miot_device"
  ];

  meta = {
    description = "Python library and console tool for controlling Xiaomi smart appliances";
    homepage = "https://github.com/rytilahti/python-miio";
    license = lib.licenses.gpl3Only;
    mainProgram = "miiocli";
  };
}
