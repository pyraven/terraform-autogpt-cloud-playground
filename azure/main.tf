provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "autogpt_rg" {
  name     = "autogpt-rg"
  location = "West US"
}

resource "azurerm_virtual_network" "autogpt_vnet" {
  name                = "autogpt-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.autogpt_rg.location
  resource_group_name = azurerm_resource_group.autogpt_rg.name
}

resource "azurerm_subnet" "autogpt_public_subnet" {
  name                 = "autogpt-public-subnet"
  virtual_network_name = azurerm_virtual_network.autogpt_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  resource_group_name  = azurerm_resource_group.autogpt_rg.name
}

resource "azurerm_public_ip" "autogpt_ip" {
  name                = "autogpt-ip"
  location            = azurerm_resource_group.autogpt_rg.location
  resource_group_name = azurerm_resource_group.autogpt_rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "autogpt_nic" {
  name                = "autogpt-nic"
  location            = azurerm_resource_group.autogpt_rg.location
  resource_group_name = azurerm_resource_group.autogpt_rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.autogpt_public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.autogpt_ip.id
  }
}

resource "azurerm_network_security_group" "ssh_access" {
  name                = "ssh-access"
  location            = azurerm_resource_group.autogpt_rg.location
  resource_group_name = azurerm_resource_group.autogpt_rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = azurerm_public_ip.autogpt_ip.ip_address
  }
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_key" {
  filename = "linux-key-pair"
  content  = tls_private_key.key.private_key_pem
}

resource "azurerm_linux_virtual_machine" "autogpt_server" {
  name                = "autogpt-server"
  location            = azurerm_resource_group.autogpt_rg.location
  resource_group_name = azurerm_resource_group.autogpt_rg.name
  size                = "Standard_B2s"
  admin_username      = "autogpt-server"
  network_interface_ids = [
    azurerm_network_interface.autogpt_nic.id
  ]

  admin_ssh_key {
    username   = "autogpt-server"
    public_key = tls_private_key.key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-10"
    sku       = "10"
    version   = "latest"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.autogpt_ip.ip_address
      user        = "autogpt-server"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y docker.io git screen",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker $(whoami)"
    ]
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.autogpt_ip.ip_address
      user        = "autogpt-server"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "git clone -b stable https://github.com/Significant-Gravitas/Auto-GPT.git",
      "cd Auto-GPT/",
      "cp .env.template .env",
      "sed -i 's/OPENAI_API_KEY=your-openai-api-key/OPENAI_API_KEY=${var.openai_key}/g' .env",
      "docker build -t autogpt .",
      "echo alias start=\\\"docker run -it --env-file=.env -v $PWD/auto_gpt_workspace:/home/root/auto_gpt_workspace autogpt --continuous\\\" >> ~/.bash_profile"
    ]
  }
}

output "ssh_command" {
  value = "ssh -i ${local_file.ssh_key.filename} autogpt-server@${azurerm_public_ip.autogpt_ip.ip_address}"
}