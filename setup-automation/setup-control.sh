################################################ UPDATE ME, PLEASE! ################################################
#!/bin/bash
su rhel -c 'ssh-keygen -f /home/rhel/.ssh/id_rsa -q -N ""'
nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.10/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0
echo "192.168.1.10 control.lab control" >> /etc/hosts


# # ## setup rhel user
# touch /etc/sudoers.d/rhel_sudoers
# echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
# cp -a /root/.ssh/* /home/$USER/.ssh/.
# chown -R rhel:rhel /home/$USER/.ssh

# Create an inventory file for this environment
tee /tmp/inventory << EOF
[nodes]
node01
node02

[storage]
storage01

[all]
node01
node02

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF
# sudo chown rhel:rhel /tmp/inventory


# creates a playbook to setup environment
tee /tmp/setup.yml << EOF
---
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
    SN_HOST_VAR: "{{ '{{' }} SN_HOST {{ '}}' }}"
    SN_USER_VAR: "{{ '{{' }} SN_USERNAME {{ '}}' }}"
    SN_PASSWORD_VAR: "{{ '{{' }} SN_PASSWORD {{ '}}' }}"
    MICROSOFT_AD_LDAP_SERVER_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_SERVER {{ '}}' }}"
    MICROSOFT_AD_LDAP_PASSWORD_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_PASSWORD {{ '}}' }}"
    MICROSOFT_AD_LDAP_USERNAME_VAR: "{{ '{{' }} MICROSOFT_AD_LDAP_USERNAME {{ '}}' }}"

  tasks:

###############CREDENTIALS###############

  - name: (EXECUTION) add App machine credential
    ansible.controller.credential:
      name: 'Application Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: (EXECUTION) add Windows machine credential
    ansible.controller.credential:
      name: 'Windows DB Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: Administrator
        password: Ansible123!

  - name: add Cisco machine credential
    ansible.controller.credential:
      name: 'Network'
      organization: Default
      credential_type: Machine
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
       username: joe
      # password: secret
       ssh_key_data: "{{ lookup('file', '/home/rhel/.ssh/id_rsa') }}"
      # ssh_key_unlock: "passphrase"

  - name: (EXECUTION) add Vault
    ansible.controller.credential:
      name: 'Windows Vault'
      organization: Default
      credential_type: Vault
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        vault_password: ansible

  - name: (EXECUTION) add Controller Vault
    ansible.controller.credential:
      name: 'Controller Vault'
      organization: Default
      credential_type: Vault
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        vault_password: ansible


###############EE###############

  - name: Add Network EE
    ansible.controller.execution_environment:
      name: "Edge_Network_ee"
      image: quay.io/acme_corp/network-ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows EE
    ansible.controller.execution_environment:
      name: "Windows_ee"
      image: quay.io/nmartins/windows_ee_rs
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add EE to the controller instance
    ansible.controller.execution_environment:
      name: "RHEL EE"
      image: quay.io/acme_corp/rhel_90_ee_25:latest
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add EE to the controller instance
    ansible.controller.execution_environment:
      name: "Controller_ee"
      image: quay.io/nmartins/cac-25_ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

###############INVENTORY###############

  - name: Add Video platform inventory
    ansible.controller.inventory:
      name: "Video Platform Inventory"
      description: "Nodes used for streaming"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Streaming Server hosts
    ansible.controller.host:
      name: "{{ item }}"
      description: "Application Nodes"
      inventory: "Video Platform Inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - haproxy
      - DBServer01

  # - name: Add Streaming server group
  #   ansible.controller.group:
  #     name: "webservers"
  #     description: "Application Nodes"
  #     inventory: "Video Platform Inventory"
  #     hosts:
  #       - DBServer01
  #     variables:
  #       ansible_user: rhel
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Streaming server group
    ansible.controller.group:
      name: "loadbalancer"
      description: "Application Nodes"
      inventory: "Video Platform Inventory"
      hosts:
        - haproxy
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  #   # Network
 
  - name: Add Edge Network Devices
    ansible.controller.inventory:
      name: "Edge Network"
      description: "Network for delivery"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Cisco
    ansible.controller.host:
      name: "cisco"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      
  - name: Add CORE Network Group
    ansible.controller.group:
      name: "Core"
      description: "EOS Network"
      inventory: "Edge Network"
      hosts:
        - cisco
      variables:
        ansible_user: admin
        ansible_network_os: cisco.ios.ios
        ansible_connection: network_cli
        ansible_become: yes
        ansible_become_method: enable
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name:  Add Windows Inventory
    ansible.controller.inventory:
     name: "Windows Servers"
     description: "Win Infrastructure"
     organization: "Default"
     state: present
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false
     variables:
       ansible_winrm_transport: credssp

  - name: Add Windows Inventory Host
    ansible.controller.host:
     name: "WindowsAD01"
     description: "Directory Servers"
     inventory: "Windows Servers"
     state: present
     enabled: true
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false
     variables:
       ansible_host: windows

  - name: Add Windows Inventory Host
    ansible.controller.host:
     name: "DBServer01"
     description: "Database Server"
     inventory: "Windows Servers"
     state: present
     enabled: true
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false
     variables:
       ansible_host: dbserver

  - name: Create group with extra vars
    ansible.controller.group:
      name: "windows"
      inventory: "Windows Servers"
      hosts:
        - WindowsAD01
        - DBServer01
      state: present
      variables:
        ansible_connection: winrm
        ansible_port: 5986
        ansible_winrm_server_cert_validation: ignore
        ansible_winrm_transport: credssp
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Create group with extra vars
    ansible.controller.group:
      name: "domain_controllers"
      inventory: "Windows Servers"
      hosts:
        - WindowsAD01
      state: present
      variables:
        ansible_connection: winrm
        ansible_port: 5986
        ansible_winrm_server_cert_validation: ignore
        ansible_winrm_transport: credssp
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Create group with extra vars
    ansible.controller.group:
      name: "database_servers"
      inventory: "Windows Servers"
      hosts:
        - DBServer01
      state: present
      variables:
        ansible_connection: winrm
        ansible_port: 5986
        ansible_winrm_server_cert_validation: ignore
        ansible_winrm_transport: credssp
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

        
###############TEMPLATES###############

  - name: Add project roadshow
    ansible.controller.project:
      name: "Roadshow"
      description: "Roadshow Content"
      organization: "Default"
      scm_type: git
      scm_url: http://gitea:3000/student/aap25-roadshow-content.git       ##ttps://github.com/nmartins0611/aap25-roadshow-content.git
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  # - name: Add Get IP Template
  #   ansible.controller.job_template:
  #     name: "Get Server IP"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Video Platform Inventory"
  #     project: "Roadshow"
  #     playbook: "playbooks/section02/get_ip.yml"
  #     execution_environment: "RHEL EE"
  #     credentials:
  #       - "Application Nodes"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Windows Setup Template
    ansible.controller.job_template:
      name: "Windows Domain Controller"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/windows_ad.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows App Template
    ansible.controller.job_template:
      name: "Windows Server Applications"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/windows_apps.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  # - name: Add Windows Setup Template
  #   ansible.controller.job_template:
  #     name: "Windows Users/Groups"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Windows Servers"
  #     project: "Roadshow"
  #     playbook: "playbooks/section02/users_groups.yml"
  #     execution_environment: "Windows_ee"
  #     credentials:
  #       - "Windows DB Nodes"
  #       - "Windows Vault"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Windows Setup Template
    ansible.controller.job_template:
      name: "Windows Registry keys"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/registry_keys.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  # - name: Add Windows App Template
  #   ansible.controller.job_template:
  #     name: "Windows Install Application"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Windows Servers"
  #     project: "Roadshow"
  #     playbook: "playbooks/section02/windows_install_app.yml"
  #     execution_environment: "Windows_ee"
  #     credentials:
  #       - "Windows DB Nodes"
  #     state: "present"
  #     survey_enabled: true
  #     survey_spec:
  #          {
  #            "name": "Install Applications",
  #            "description": "Install using Chocolatey",
  #            "spec": [
  #              {
  #   	          "type": "text",
  #   	          "question_name": "Please provide the application you want to install",
  #             	"question_description": "Application from Chocolatey",
  #             	"variable": "application",
  #             	"required": true,
  #              },
  #             ]
  #          }
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Windows OU Template
    ansible.controller.job_template:
      name: "Windows Users and OU"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/users_groups.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
        - "Windows Vault"
      state: "present"
      survey_enabled: true
      survey_spec:
           {
             "name": "Configure OU and Groups",
             "description": "Domain accounts",
             "spec": [
               {
    	          "type": "text",
    	          "question_name": "Please provide the OU you want to create",
              	"question_description": "Automaton OU",
              	"variable": "org_unit",
              	"required": true,
               },
               {
    	          "type": "text",
    	          "question_name": "Please Provide your group:",
              	"question_description": "User Group",
              	"variable": "group_name",
              	"required": true,
               }
              ]
           }
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows Setup Template
    ansible.controller.job_template:
      name: "Windows Join Domain"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/join_ad.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
        - "Windows Vault"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Node-Provision Setup Template
    ansible.controller.job_template:
      name: "Deploy Node"
      job_type: "run"
      organization: "Default"
      inventory: "Demo Inventory"
      project: "Roadshow"
      playbook: "playbooks/section02/deploy_node.yml"
      execution_environment: "Controller_ee"
      credentials:
        - "Application Nodes"
        - 'Controller Vault'
      state: "present"
      survey_enabled: true
      survey_spec:
           {
             "name": "Provision System",
             "description": "System Name",
             "spec": [
               {
    	          "type": "text",
    	          "question_name": "Please provide the name of your system",
              	"question_description": "Node Number",
              	"variable": "node_name",
              	"required": true,
               }
              ]
           }
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  # - name: Add Windows Setup Template
  #   ansible.controller.job_template:
  #     name: "RHEL Join Domain"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Video Platform Inventory"
  #     project: "Roadshow"
  #     playbook: "playbooks/section02/join_ad.yml"
  #     execution_environment: "Windows_ee"
  #     credentials:
  #       - "Windows DB Nodes"
  #       - "Windows Vault"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  # - name: Add Cisco Setup Template
  #   ansible.controller.job_template:
  #     name: "Network Changes"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Core"
  #     project: "Roadshow"
  #     playbook: "playbooks/section02/network_config.yml"
  #     execution_environment: "Edge_Network_ee"
  #     credentials:
  #       - "Network"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Windows Application Template
    ansible.controller.job_template:
      name: "Windows Deploy WebApp"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Servers"
      project: "Roadshow"
      playbook: "playbooks/section02/windows_webapp.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows DB Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL Application Template
    ansible.controller.job_template:
      name: "RHEL Deploy WebApp"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section02/rhel_webapp.yml"
      execution_environment: "RHEL EE"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL LDAP Template
    ansible.controller.job_template:
      name: "RHEL Join AD"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section02/join_ad_rhel.yml"
      execution_environment: "RHEL EE"
      credentials:
        - "Application Nodes"
        - "Controller Vault"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add HAproxy Setup Template
    ansible.controller.job_template:
      name: "Configure Loadbalancer"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section02/mod_haproxy.yml"
      execution_environment: "RHEL EE"
      credentials:
        - "Application Nodes"
      state: "present"
      survey_enabled: true
      survey_spec:
           {
             "name": "Add system to loadbalancer",
             "description": "System Name",
             "spec": [
               {
    	          "type": "text",
    	          "question_name": "Please provide the name of your system",
              	"question_description": "Machine",
              	"variable": "host",
              	"required": true,
               }
              ]
           }
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false


EOF


ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml
