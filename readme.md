## Prerequisites:
- [Install Terraform](https://developer.hashicorp.com/terraform/tutorials)
- [AWS Account](https://aws.amazon.com/console/) + [Authentication](https://docs.aws.amazon.com/cli/latest/userguide/cli-authentication-user.html)
- [OpenAI API Key](https://platform.openai.com/account/api-keys)
- [Find out your IPv4 address](https://whatismyipaddress.com/)

### Then fill out the variables.tf file.

```bash
terraform fmt
terraform init
terraform plan
terraform apply
chmod 400 linux-key-pair.pem
ssh -i linux-key-pair.pem ec2-user@<ip_address>
cd Auto-GPT/
screen
source ~/.bash_profile
start
```
### When you are done, destroy everything to prevent cost.
```bash
terraform destroy
```