################################################ UPDATE ME, PLEASE! ################################################
#!/bin/bash
su rhel -c 'ssh-keygen -f /home/rhel/.ssh/id_rsa -q -N ""'
nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.10/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0
echo "192.168.1.10 control.lab control" >> /etc/hosts
echo "192.168.1.11 podman.lab podman" >> /etc/hosts



# # ## setup rhel user
# touch /etc/sudoers.d/rhel_sudoers
# echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
# cp -a /root/.ssh/* /home/$USER/.ssh/.
# chown -R rhel:rhel /home/$USER/.ssh

# Create an inventory file for this environment
tee /tmp/inventory << EOF

[windowssrv]
windows ansible_host=windows ansible_user=Administrator ansible_password=Ansible123! ansible_connection=winrm ansible_port=5986 ansible_winrm_scheme=https ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore

[all]
podman
windowssrv

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF
# sudo chown rhel:rhel /tmp/inventory

cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: controller
controller_validate_certs: false
ansible_python_interpreter: /usr/bin/python3
controller_ee: Windows_ee
student_user: student
student_password: learn_ansible
controller_admin_user: admin
controller_admin_password: "ansible123!"
host_key_checking: false
custom_facts_dir: "/etc/ansible/facts.d"
custom_facts_file: custom_facts.fact
admin_username: admin
admin_password: ansible123!
repo_user: rhel
default_tag_name: "0.0.1"
lab_organization: ACME

EOF

# Set up podman (gitea)
tee /tmp/test.yml << EOF
---
- name: Setup podman and services
  hosts: podman
  gather_facts: true
  tasks:

  - name: put password in /tmp
    ansible.builtin.command:
      cmd: echo "task {{ lookup('ansible.builtin.env', 'admin_password') }}" >> /tmp/passwd

...
EOF

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/test.yml

# SET UP WINDOWS
cat <<EOF | tee /tmp/domain.yml

---
- 
  hosts: windowssrv
  gather_facts: true
  collections:
   - ansible.windows

  vars:
    domain_state: domain
    workgrp_name: WORKGROUP
    domain_ou: 
    domain_admin: administrator
    domain_admin_pass: ''


  tasks:

    - name: Deploying webservers on Windows nodes
      block:
        - name: Add host to the Windows AD
          microsoft.ad.membership:
           dns_domain_name: prometheus.io
           hostname: "{{ ansible_hostname }}"
           domain_admin_user: administrator@prometheus.io
           domain_admin_password: ''
        #  domain_ou_path:  "{{ domain_ou }}" "OU=Windows,OU=Servers,DC=ansible,DC=vagrant"
           workgroup_name: "{{ workgrp_name }}"
           state: "{{ domain_state }}"
           reboot: true
          tags:
            - add_domain
            - never

        - name: Demote Machine to Workgroup
          microsoft.ad.membership:
           hostname: "{{ ansible_netbios_name }}"
           domain_admin_user: administrator@prometheus.io
           domain_admin_password: ''
           workgroup_name: "{{ workgrp_name }}"
           state: workgroup
          tags:
            - remove_domain
            - never

        - name: Update Windows nodes
          ansible.windows.win_updates:
           category_names:
             - SecurityUpdates
             - CriticalUpdates
             - UpdateRollups
          register: server_updated
          tags:
            - always

    - name: Firewall rule to allow RDP on TCP port 3389
      win_firewall_rule:
       name: Remote Desktop
       localport: 3389
       action: allow
       direction: in
       protocol: tcp
       profiles: domain,private,public
       state: present
       enabled: yes        
      tags:
        - add_domain
        - firewall
        - never

    - name: Firewall rule to allow RDP on TCP port 5986
      win_firewall_rule:
        name: WinRM
        localport: 5986
        action: allow
        direction: in
        protocol: tcp
        profiles: domain,private,public
        state: present
        enabled: yes        
      tags:
        - add_domain
        - firewall
        - never

    - name: Reboot host if install requires it
      ansible.windows.win_reboot:
      when: server_updated.reboot_required

EOF

############################ CONTROLLER CONFIG

cat <<EOF | tee /tmp/controller-setup.yml
## Controller setup
- name: Controller config for Windows Getting Started
  hosts: controller.acme.example.com
  gather_facts: true
    
  tasks:
   # Create auth login token
    - name: get auth token and restart automation-controller if it fails
      block:
        - name: Refresh facts
          setup:

        - name: Create oauth token
          awx.awx.token:
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      rescue:
        - name: In rescue block for auth token
          debug:
            msg: "failed to get auth token. Restarting automation controller service"

        - name: restart the controller service
          ansible.builtin.service:
            name: automation-controller
            state: restarted

        - name: Ensure tower/controller is online and working
          uri:
            url: https://localhost/api/v2/ping/
            method: GET
            user: "{{ admin_username }}"
            password: "{{ admin_password }}"
            validate_certs: false
            force_basic_auth: true
          register: controller_online
          until: controller_online is success
          delay: 3
          retries: 5

        - name: Retry getting auth token
          awx.awx.token:
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      always:
        - name: Create fact.d dir
          ansible.builtin.file:
            path: "{{ custom_facts_dir }}"
            state: directory
            recurse: yes
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: 0755
          become: true

        - name: Create _auth_token custom fact
          ansible.builtin.copy:
            content: "{{ _auth_token.ansible_facts }}"
            dest: "{{ custom_facts_dir }}/{{ custom_facts_file }}"
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: 0644
          become: true
      check_mode: false
      when: ansible_local.custom_facts.controller_token is undefined
      tags:
        - auth-token

    - name: refresh facts
      setup:
        filter:
          - ansible_local
      tags:
        - always

    - name: create auth token fact
      ansible.builtin.set_fact:
        auth_token: "{{ ansible_local.custom_facts.controller_token }}"
        cacheable: true
      check_mode: false
      when: auth_token is undefined
      tags:
        - always
 
    - name: Ensure tower/controller is online and working
      uri:
        url: https://localhost/api/v2/ping/
        method: GET
        user: "{{ admin_username }}"
        password: "{{ admin_password }}"
        validate_certs: false
        force_basic_auth: true
      register: controller_online
      until: controller_online is success
      delay: 3
      retries: 5
      tags:
        - controller-config

# Controller objects
    - name: Add Organization
      awx.awx.organization:
        name: "{{ lab_organization }}"
        description: "ACME Corp Organization"
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        validate_certs: false
      tags:
        - controller-config
        - controller-org
  
    - name: Add Instruqt Windows EE
      awx.awx.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/nmartins/windows_ee"
        pull: missing
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-ees

    - name: Create student admin user
      awx.awx.user:
        superuser: true
        username: "{{ student_user }}"
        password: "{{ student_password }}"
        email: student@acme.example.com
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-users    
        
    - name: Create Inventory
      awx.awx.inventory:
       name: "Servers"
       description: "Our Server environment"
       organization: "ACME"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Add host to inventory
      awx.awx.host:
        name: "windows"
        inventory: "Servers" 
        state: present
        controller_config_file: "/tmp/controller.cfg"

    - name: Create group with extra vars
      awx.awx.group:
        name: "Windows_Servers"
        inventory: "Servers"
        hosts:
          windows
        state: present
        variables:
          ansible_connection: winrm
          ansible_port: 5986
          ansible_winrm_server_cert_validation: ignore
          ansible_winrm_transport: credssp
        controller_config_file: "/tmp/controller.cfg"
      register: inv_group
 
    - name: Add machine credential
      awx.awx.credential:
       name: "Windows Host"
       credential_type: Machine
       organization: Default
       inputs:
        username: instruqt
        password: Passw0rd!
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Add project
      awx.awx.project:
       name: "Active-Directory AAP"
       description: "Active Directory Management"
       organization: "Default"
       scm_url: http://gitea:3000/student/aap_activedirectory.git
       scm_type: "git"
       scm_branch: "main"
       scm_clean: true
       scm_update_on_launch: true
       state: present
       controller_config_file: "/tmp/controller.cfg"

    # - name: Create IIS template
    #   awx.awx.job_template:
    #    name: "Setup IIS"
    #    job_type: "run"
    #    organization: "Default"
    #    inventory: "Servers"
    #    project: "Active-Directory AAP"
    #    playbook: "setup_iis.yml"
    #    execution_environment: "Windows_ee"
    #    credentials:
    #     - "Windows Host"
    #    state: "present"
    #    controller_config_file: "/tmp/controller.cfg"


EOF

cat <<EOF | tee /tmp/controller.cfg
host: localhost
username: admin
password: ansible123!
verify_ssl = false
EOF

cat <<EOF | tee /tmp/domain_controller.yml

---
- 
  hosts: active-directory
  gather_facts: true
  collections:
   - ansible.windows

  vars:
    domain_state: domain
    workgrp_name: WORKGROUP
    domain_ou: 
    domain_admin: administrator
    domain_admin_pass: 'ansible4Ever'

  tasks:

    - name: Deploying webservers on Windows nodes
      block:
        - name: Add host to the Windows AD
          microsoft.ad.membership:
           dns_domain_name: prometheus.io
           hostname: "{{ ansible_hostname }}"
           domain_admin_user: "{{ domain_admin }}"
           domain_admin_password: "{{ domain_admin_pass }}"
           workgroup_name: "{{ workgrp_name }}"
           state: "{{ domain_state }}"
           reboot: true

    - name: Reboot host if install requires it
      ansible.windows.win_reboot:
      when: server_updated.reboot_required

EOF
# # creates a playbook to setup environment
# tee /tmp/setup.yml << EOF
# ---
# ### Automation Controller setup 
# ###
# - name: Setup Controller 
#   hosts: localhost
#   connection: local
#   collections:
#     - ansible.controller
#   vars:
#     SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
#     SN_HOST_VAR: "{{ '{{' }} SN_HOST {{ '}}' }}"
#     SN_USER_VAR: "{{ '{{' }} SN_USERNAME {{ '}}' }}"
#     SN_PASSWORD_VAR: "{{ '{{' }} SN_PASSWORD {{ '}}' }}"
#     MICROSOFT_AD_LDAP_SERVER_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_SERVER {{ '}}' }}"
#     MICROSOFT_AD_LDAP_PASSWORD_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_PASSWORD {{ '}}' }}"
#     MICROSOFT_AD_LDAP_USERNAME_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_USERNAME {{ '}}' }}"

#   tasks:

# ###############CREDENTIALS###############

#   - name: (EXECUTION) add App machine credential
#     ansible.controller.credential:
#       name: 'Application Nodes'
#       organization: Default
#       credential_type: Machine
#       controller_host: "https://{{ ansible_host }}"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
#       inputs:
#         username: rhel
#         password: ansible123!

#   - name: (EXECUTION) add Windows machine credential
#     ansible.controller.credential:
#       name: 'Windows DB Nodes'
#       organization: Default
#       credential_type: Machine
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
#       inputs:
#         username: Administrator
#         password: Ansible123!

#   - name: (EXECUTION) add Vault
#     ansible.controller.credential:
#       name: 'Windows Vault'
#       organization: Default
#       credential_type: Vault
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
#       inputs:
#         vault_password: ansible

#   - name: (EXECUTION) add Controller Vault
#     ansible.controller.credential:
#       name: 'Controller Vault'
#       organization: Default
#       credential_type: Vault
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
#       inputs:
#         vault_password: ansible


# ###############EE###############

#   - name: Add Network EE
#     ansible.controller.execution_environment:
#       name: "Edge_Network_ee"
#       image: quay.io/acme_corp/network-ee
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows EE
#     ansible.controller.execution_environment:
#       name: "Windows_ee"
#       image: quay.io/nmartins/windows_ee_rs
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add EE to the controller instance
#     ansible.controller.execution_environment:
#       name: "RHEL EE"
#       image: quay.io/acme_corp/rhel_90_ee_25:latest
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add EE to the controller instance
#     ansible.controller.execution_environment:
#       name: "Controller_ee"
#       image: quay.io/nmartins/cac-25_ee
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

# ###############INVENTORY###############

#   - name: Add Video platform inventory
#     ansible.controller.inventory:
#       name: "Video Platform Inventory"
#       description: "Nodes used for streaming"
#       organization: "Default"
#       state: present
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Streaming Server hosts
#     ansible.controller.host:
#       name: "{{ item }}"
#       description: "Application Nodes"
#       inventory: "Video Platform Inventory"
#       state: present
#       enabled: true
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
#     loop:
#       - haproxy
#       - DBServer01

#   - name: Add Streaming server group
#     ansible.controller.group:
#       name: "loadbalancer"
#       description: "Application Nodes"
#       inventory: "Video Platform Inventory"
#       hosts:
#         - haproxy
#       variables:
#         ansible_user: rhel
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   #   # Network
 
#   - name: Add Edge Network Devices
#     ansible.controller.inventory:
#       name: "Edge Network"
#       description: "Network for delivery"
#       organization: "Default"
#       state: present
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Cisco
#     ansible.controller.host:
#       name: "cisco"
#       description: "Edge Leaf"
#       inventory: "Edge Network"
#       state: present
#       enabled: true
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false
      
#   - name: Add CORE Network Group
#     ansible.controller.group:
#       name: "Core"
#       description: "EOS Network"
#       inventory: "Edge Network"
#       hosts:
#         - cisco
#       variables:
#         ansible_user: admin
#         ansible_network_os: cisco.ios.ios
#         ansible_connection: network_cli
#         ansible_become: yes
#         ansible_become_method: enable
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name:  Add Windows Inventory
#     ansible.controller.inventory:
#      name: "Windows Servers"
#      description: "Win Infrastructure"
#      organization: "Default"
#      state: present
#      controller_host: "https://localhost"
#      controller_username: admin
#      controller_password: ansible123!
#      validate_certs: false
#      variables:
#        ansible_winrm_transport: credssp

#   - name: Add Windows Inventory Host
#     ansible.controller.host:
#      name: "WindowsAD01"
#      description: "Directory Servers"
#      inventory: "Windows Servers"
#      state: present
#      enabled: true
#      controller_host: "https://localhost"
#      controller_username: admin
#      controller_password: ansible123!
#      validate_certs: false
#      variables:
#        ansible_host: windows

#   - name: Add Windows Inventory Host
#     ansible.controller.host:
#      name: "DBServer01"
#      description: "Database Server"
#      inventory: "Windows Servers"
#      state: present
#      enabled: true
#      controller_host: "https://localhost"
#      controller_username: admin
#      controller_password: ansible123!
#      validate_certs: false
#      variables:
#        ansible_host: dbserver

#   - name: Create group with extra vars
#     ansible.controller.group:
#       name: "windows"
#       inventory: "Windows Servers"
#       hosts:
#         - WindowsAD01
#         - DBServer01
#       state: present
#       variables:
#         ansible_connection: winrm
#         ansible_port: 5986
#         ansible_winrm_server_cert_validation: ignore
#         ansible_winrm_transport: credssp
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Create group with extra vars
#     ansible.controller.group:
#       name: "domain_controllers"
#       inventory: "Windows Servers"
#       hosts:
#         - WindowsAD01
#       state: present
#       variables:
#         ansible_connection: winrm
#         ansible_port: 5986
#         ansible_winrm_server_cert_validation: ignore
#         ansible_winrm_transport: credssp
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Create group with extra vars
#     ansible.controller.group:
#       name: "database_servers"
#       inventory: "Windows Servers"
#       hosts:
#         - DBServer01
#       state: present
#       variables:
#         ansible_connection: winrm
#         ansible_port: 5986
#         ansible_winrm_server_cert_validation: ignore
#         ansible_winrm_transport: credssp
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

        
# ###############TEMPLATES###############

#   - name: Add project roadshow
#     ansible.controller.project:
#       name: "Roadshow"
#       description: "Roadshow Content"
#       organization: "Default"
#       scm_type: git
#       scm_url: http://gitea:3000/student/aap25-roadshow-content.git       ##ttps://github.com/nmartins0611/aap25-roadshow-content.git
#       state: present
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows Setup Template
#     ansible.controller.job_template:
#       name: "Windows Domain Controller"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/windows_ad.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows App Template
#     ansible.controller.job_template:
#       name: "Windows Server Applications"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/windows_apps.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows Setup Template
#     ansible.controller.job_template:
#       name: "Windows Registry keys"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/registry_keys.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows OU Template
#     ansible.controller.job_template:
#       name: "Windows Users and OU"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/users_groups.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#         - "Windows Vault"
#       state: "present"
#       survey_enabled: true
#       survey_spec:
#            {
#              "name": "Configure OU and Groups",
#              "description": "Domain accounts",
#              "spec": [
#                {
#     	          "type": "text",
#     	          "question_name": "Please provide the OU you want to create",
#               	"question_description": "Automaton OU",
#               	"variable": "org_unit",
#               	"required": true,
#                },
#                {
#     	          "type": "text",
#     	          "question_name": "Please Provide your group:",
#               	"question_description": "User Group",
#               	"variable": "group_name",
#               	"required": true,
#                }
#               ]
#            }
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows Setup Template
#     ansible.controller.job_template:
#       name: "Windows Join Domain"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/join_ad.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#         - "Windows Vault"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Node-Provision Setup Template
#     ansible.controller.job_template:
#       name: "Deploy Node"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Demo Inventory"
#       project: "Roadshow"
#       playbook: "playbooks/section02/deploy_node.yml"
#       execution_environment: "Controller_ee"
#       credentials:
#         - "Application Nodes"
#         - 'Controller Vault'
#       state: "present"
#       survey_enabled: true
#       survey_spec:
#            {
#              "name": "Provision System",
#              "description": "System Name",
#              "spec": [
#                {
#     	          "type": "text",
#     	          "question_name": "Please provide the name of your system",
#               	"question_description": "Node Number",
#               	"variable": "node_name",
#               	"required": true,
#                }
#               ]
#            }
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add Windows Application Template
#     ansible.controller.job_template:
#       name: "Windows Deploy WebApp"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Windows Servers"
#       project: "Roadshow"
#       playbook: "playbooks/section02/windows_webapp.yml"
#       execution_environment: "Windows_ee"
#       credentials:
#         - "Windows DB Nodes"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add RHEL Application Template
#     ansible.controller.job_template:
#       name: "RHEL Deploy WebApp"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Video Platform Inventory"
#       project: "Roadshow"
#       playbook: "playbooks/section02/rhel_webapp.yml"
#       execution_environment: "RHEL EE"
#       credentials:
#         - "Application Nodes"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add RHEL LDAP Template
#     ansible.controller.job_template:
#       name: "RHEL Join AD"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Video Platform Inventory"
#       project: "Roadshow"
#       playbook: "playbooks/section02/join_ad_rhel.yml"
#       execution_environment: "RHEL EE"
#       credentials:
#         - "Application Nodes"
#         - "Controller Vault"
#       state: "present"
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false

#   - name: Add HAproxy Setup Template
#     ansible.controller.job_template:
#       name: "Configure Loadbalancer"
#       job_type: "run"
#       organization: "Default"
#       inventory: "Video Platform Inventory"
#       project: "Roadshow"
#       playbook: "playbooks/section02/mod_haproxy.yml"
#       execution_environment: "RHEL EE"
#       credentials:
#         - "Application Nodes"
#       state: "present"
#       survey_enabled: true
#       survey_spec:
#            {
#              "name": "Add system to loadbalancer",
#              "description": "System Name",
#              "spec": [
#                {
#     	          "type": "text",
#     	          "question_name": "Please provide the name of your system",
#               	"question_description": "Machine",
#               	"variable": "host",
#               	"required": true,
#                }
#               ]
#            }
#       controller_host: "https://localhost"
#       controller_username: admin
#       controller_password: ansible123!
#       validate_certs: false


# EOF


ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml
