################################################ UPDATE ME, PLEASE! ################################################ 
# File sourced from zt-ans-bu-eda-controller

#!/bin/bash
# nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
# nmcli connection up eth1
curl -k  -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm || true

subscription-manager status >/dev/null 2>&1 || \
  subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY} --force
setenforce 0
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
chmod 440 /etc/sudoers.d/rhel_sudoers
sudo -u rhel mkdir -p /home/rhel/.ssh
sudo -u rhel chmod 700 /home/rhel/.ssh
if [ ! -f /home/rhel/.ssh/id_rsa ]; then
sudo -u rhel ssh-keygen -q -t rsa -b 4096 -C "rhel@$(hostname)" -f /home/rhel/.ssh/id_rsa -N ""
fi
sudo -u rhel chmod 600 /home/rhel/.ssh/id_rsa*

echo "Registered and Ready"

dnf install ansible-core -y

ansible-galaxy collection install community.general

tee /tmp/setup.yml << EOF
---
###
### Podman setup 
###
- name: Setup podman and services
  hosts: localhost
  gather_facts: no
  vars:
    student_user: 'student'
    student_password: 'learn_ansible'
  tasks:
    - name: Install EPEL
      ansible.builtin.package:
        name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        state: present
        disable_gpg_check: true
      become: true

      ## Lab Fix
    - name: Ensure crun is updated to the latest available version
      ansible.builtin.dnf:
        name: crun
        state: latest
      become: true

    - name: Install required packages
      ansible.builtin.package:
        name: "{{ item }}"
        state: present
      loop:
        - subversion
        - tar
        - git
        - python3-pip
        - python3-dotenv
        - tmux
        - podman-compose
      become: true

    - name: Clone gitea podman-compose project
      ansible.builtin.git:
        repo: https://github.com/cloin/gitea-podman.git
        dest: /tmp/gitea-podman
        force: true

    - name: Allow user to linger
      ansible.builtin.command: 
        cmd: loginctl enable-linger rhel
        chdir: /tmp/gitea-podman

    - name: Start gitea
      ansible.builtin.command: 
        cmd: podman-compose up -d
        chdir: /tmp/gitea-podman

    - name: Wait for gitea to start
      ansible.builtin.pause:
        seconds: 15

    - name: Set Gitea ROOT_URL to https://gitea:3000
      ansible.builtin.shell: >
        podman exec gitea sh -c "INI=/data/gitea/conf/app.ini; mkdir -p /data/gitea/conf; touch \"$INI\"; if grep -q '^ROOT_URL' \"$INI\"; then sed -i 's|^ROOT_URL.*|ROOT_URL = https://gitea:3000|' \"$INI\"; else printf '\n[server]\nROOT_URL = https://gitea:3000\n' >> \"$INI\"; fi"

    - name: Set Gitea DOMAIN to gitea
      ansible.builtin.shell: >
        podman exec gitea sh -c "INI=/data/gitea/conf/app.ini; mkdir -p /data/gitea/conf; touch \"$INI\"; if grep -q '^DOMAIN' \"$INI\"; then sed -i 's|^DOMAIN.*|DOMAIN = gitea|' \"$INI\"; else printf '\n[server]\nDOMAIN = gitea\n' >> \"$INI\"; fi"

    - name: Restart gitea
      ansible.builtin.command:
        cmd: podman restart gitea

    - name: Create repo user
      ansible.builtin.command: podman exec -u git gitea /usr/local/bin/gitea admin user create --admin --username student --password learn_ansible --email student@redhat.com
      become_user: git
      register: __output
      failed_when: __output.rc not in [ 0, 1 ]
      changed_when: '"user already exists" not in __output.stdout'

    - name: Store repo credentials in git-creds file
      ansible.builtin.copy:
        dest: /tmp/git-creds
        mode: 0644
        content: "http://{{ student_user }}:{{ student_password }}@{{ 'localhost:3000' | urlencode }}"

    - name: Configure git username
      community.general.git_config:
        name: user.name
        scope: global
        value: "student"

    - name: Configure git email address
      community.general.git_config:
        name: user.email
        scope: global
        value: "student@redhat.com"

    - name: Grab the rsa
      ansible.builtin.set_fact:
        controller_ssh: "{{ lookup('file', '/home/rhel/.ssh/id_rsa.pub') }}"

    - name: Migrate github project to gitea student user
      ansible.builtin.uri:
        url: http://localhost:3000/api/v1/repos/migrate
        method: POST
        body_format: json
        body: {"clone_addr": "https://github.com/nmartins0611/aap_and_activedirectory.git", "repo_name": "aap_activedirectory"}
        status_code: [201, 409]
        headers:
          Content-Type: "application/json"
        user: student
        password: learn_ansible
        force_basic_auth: yes
        validate_certs: no

    - name: Start prometheus with podman-compose
      ansible.builtin.command: 
        cmd: podman-compose up -d
        chdir: /tmp/gitea-podman/

EOF

ansible-playbook /tmp/setup.yml
