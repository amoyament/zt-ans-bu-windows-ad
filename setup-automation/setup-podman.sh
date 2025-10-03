################################################ UPDATE ME, PLEASE! ################################################ 
# File sourced from zt-ans-bu-eda-controller

#!/bin/bash
nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
nmcli connection up eth1
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
# nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
# nmcli connection up eth1
# # echo "192.168.1.10 control.lab control aap control.ansible.workshop" >> /etc/hosts
# # echo "192.168.1.11 podman.lab podman" >> /etc/hosts

# retry() {
#     for i in {1..3}; do
#         echo "Attempt $i: $2"
#         if $1; then
#             return 0
#         fi
#         [ $i -lt 3 ] && sleep 5
#     done
#     echo "Failed after 3 attempts: $2"
#     exit 1
# }

# retry "curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"
# retry "update-ca-trust"
# retry "rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"
# retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}"


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
  # become: true
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
    #     - python3-dotenv
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

    - name: Create repo users
      ansible.builtin.command: "{{ item }}"
      become_user: git
      register: __output
      failed_when: __output.rc not in [ 0, 1 ]
      changed_when: '"user already exists" not in __output.stdout'
      loop:
        - "podman exec -u git gitea /usr/local/bin/gitea admin user create --admin --username student --password learn_ansible --email student@example.com"
        # - "/usr/local/bin/gitea admin user create --admin --username {{ student_user }} --password {{ student_password }} --must-change-password=false --email {{ student_user }}@localhost"

    - name: Store repo credentials in git-creds file
      ansible.builtin.copy:
        dest: /tmp/git-creds
        mode: 0644
        content: "http://{{ student_user }}:{{ student_password }}@{{ 'localhost:3000' | urlencode }}"

    - name: Configure git username
      community.general.git_config:
        name: user.name
        scope: global
        value: "root"

    - name: Configure git email address
      community.general.git_config:
        name: user.email
        scope: global
        value: "root@local"

    - name: Grab the rsa
      ansible.builtin.set_fact:
        controller_ssh: "{{ lookup('file', '/home/rhel/.ssh/id_rsa.pub') }}"

    - name: Migrate github projects to gitea student user
      ansible.builtin.uri:
        url: http://localhost:3000/api/v1/repos/migrate
        method: POST
        body_format: json
        body: {"clone_addr": "{{ item.url }}", "repo_name": "{{ item.name }}"}
        status_code: [201, 409]
        headers:
          Content-Type: "application/json"
        user: student
        password: learn_ansible
        force_basic_auth: yes
        validate_certs: no
      loop:
        - {name: 'aap_activedirectory', url: 'https://github.com/nmartins0611/aap_and_activedirectory.git'}

    - name: Start prometheus with podman-compose
      ansible.builtin.command: 
        cmd: podman-compose up -d
        chdir: /tmp/gitea-podman/

    # - name: Install EPEL
    #   ansible.builtin.package:
    #     name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    #     state: present
    #     disable_gpg_check: true
    #   become: true

    #   ## Lab Fix
    # - name: Ensure crun is updated to the latest available version
    #   ansible.builtin.dnf:
    #     name: crun
    #     state: latest
    #   become: true

    # - name: Install required packages
    #   ansible.builtin.package:
    #     name: "{{ item }}"
    #     state: present
    #   loop:
    #     - git
    #     - tmux
    #     - python3-pip
    #     - podman-compose
    #     - python3-dotenv
    #   become: true


    # - name: Clone gitea podman-compose project
    #   ansible.builtin.git:
    #     repo: https://github.com/cloin/gitea-podman.git
    #     dest: /tmp/gitea-podman
    #     force: true

    # - name: Allow user to linger
    #   ansible.builtin.command: 
    #     cmd: loginctl enable-linger rhel
    #     chdir: /tmp/gitea-podman

    # - name: Start gitea
    #   ansible.builtin.command: 
    #     cmd: podman-compose up -d
    #     chdir: /tmp/gitea-podman

    # - name: Wait for gitea to start
    #   ansible.builtin.pause:
    #     seconds: 15

    # - name: Create gitea student user
    #   ansible.builtin.shell:
    #     cmd: podman exec -u git gitea /usr/local/bin/gitea admin user create --admin --username student --password learn_ansible --email student@example.com
    #   ignore_errors: true

    # - name: Migrate github projects to gitea student user
    #   ansible.builtin.uri:
    #     url: http://localhost:3000/api/v1/repos/migrate
    #     method: POST
    #     body_format: json
    #     body: {"clone_addr": "https://github.com/nmartins0611/aap_and_activedirectory.git", "repo_name": "aap_activedirectory"}
    #     status_code: [201, 409]
    #     headers:
    #       Content-Type: "application/json"
    #     user: student
    #     password: learn_ansible
    #     force_basic_auth: yes
    #     validate_certs: no

    # - name: Set the default branch to aap25 for migrated repositories
    #   ansible.builtin.uri:
    #     url: "http://localhost:3000/api/v1/repos/student/aap_activedirectory"
    #     method: PATCH
    #     body_format: json
    #     body:
    #       default_branch: "main"
    #     headers:
    #       Content-Type: "application/json"
    #     user: student
    #     password: learn_ansible
    #     force_basic_auth: yes
    #     validate_certs: no
    #   delegate_to: localhost

    # - name: Clone the specific branch from the migrated repo
    #   ansible.builtin.git:
    #     repo: "http://localhost:3000/student/aap_activedirectory.git"
    #     dest: "/tmp/aap_activedirectory"
    #     version: "main"
    #     force: true

    # - name: Start node_exporter and webhook services with podman-compose
    #   ansible.builtin.command:
    #     cmd: podman-compose up -d
    #     chdir: "/tmp/aap_activedirectory/{{ item }}"
    #   loop:
    #     - node_exporter
    #     # - webhook

    # # - name: Wait for services to start
    # #   ansible.builtin.pause:
    # #     seconds: 15

    # - name: Start prometheus with podman-compose
    #   ansible.builtin.command: 
    #     cmd: podman-compose up -d
    #     chdir: /tmp/aap_activedirectory/prometheus
EOF


ansible-playbook /tmp/setup.yml






# echo "### Starting Podman Setup Script ###"

# # -----------------------------------------------------------------------------
# ## 1. Install System Packages
# # -----------------------------------------------------------------------------
# echo "--> Installing EPEL repository..."
# # The --nogpgcheck flag is equivalent to disable_gpg_check: true
# sudo dnf install -y --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# echo "--> Ensuring 'crun' is updated to the latest version..."
# sudo dnf update -y crun

# echo "--> Installing required packages..."
# PACKAGES=(
#     "git"
#     "tmux"
#     "python3-pip"
#     "podman-compose"
#     "python3-dotenv"
# )
# sudo dnf install -y "${PACKAGES[@]}"

# # -----------------------------------------------------------------------------
# ## 2. Configure Gitea Repositories
# # -----------------------------------------------------------------------------
# REPOS=("eda-project" "eda-alertmanager")
# echo "--> Setting default branch to 'aap25' in Gitea for repositories..."
# for repo in "${REPOS[@]}"; do
#     echo "  - Updating ${repo}"
#     # Use curl to send a PATCH request to the Gitea API
#     # The --insecure flag is equivalent to validate_certs: no
#     curl --insecure --user gitea:gitea --request PATCH \
#          --header "Content-Type: application/json" \
#          --data '{"default_branch": "aap25"}' \
#          "http://gitea:3000/api/v1/repos/student/${repo}"
# done
# # Add a newline for cleaner output
# echo ""

# # -----------------------------------------------------------------------------
# ## 3. Clone Git Repositories
# # -----------------------------------------------------------------------------
# echo "--> Cloning repositories from Gitea..."
# for repo in "${REPOS[@]}"; do
#     DEST_DIR="/tmp/${repo}"
#     REPO_URL="http://gitea:3000/student/${repo}.git"

#     echo "  - Cloning branch 'aap25' from ${REPO_URL} to ${DEST_DIR}"
    
#     # Remove the destination directory if it exists to mimic 'force: true'
#     if [ -d "$DEST_DIR" ]; then
#         echo "    - Destination ${DEST_DIR} exists. Removing it first."
#         rm -rf "$DEST_DIR"
#     fi

#     git clone --branch aap25 "${REPO_URL}" "${DEST_DIR}"
# done

# # -----------------------------------------------------------------------------
# ## 4. Start Podman Services
# # -----------------------------------------------------------------------------
# echo "--> Starting node_exporter service with podman-compose..."
# # Use a subshell to change directory temporarily
# (cd "/tmp/eda-alertmanager/node_exporter" && podman-compose up -d)

# # The webhook service was commented out in the playbook and is omitted here.

# echo "--> Starting prometheus service with podman-compose..."
# (cd "/tmp/eda-alertmanager/prometheus" && podman-compose up -d)

# echo ""
# echo "### Setup complete! ###"


# exit 0