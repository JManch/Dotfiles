{ hostname
, ...
}:
{
  imports = [
    ./${hostname}
  ];
}
