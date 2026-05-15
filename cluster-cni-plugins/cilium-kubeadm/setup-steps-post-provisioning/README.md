Installing Cilium

- note, Cilium can be installed with either the Cilium CLI or Helm


Installing Cilium (and Hubble) using the cilium CLI

step 1 - Install the cilium cli (view cilium cli documentation)
step 2 - Install the Hubble cli (view the hubble cli documentation)
step 3 - Verify that both cli's are installed 
    - `cilium version --client && hubble version`
step 4 - Install cilium using CLI
    - `cilium install --version <version from version command> --wait`
step 5 - Check cilium status & run connectivity test
    - `cilium status` 
    - `cilium connectivity test`