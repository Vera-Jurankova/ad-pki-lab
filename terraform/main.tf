resource "local_file" "test" {
  content  = "Hello from Terraform via GitHub Actions"
  filename = "C:\\temp\\terraform-test.txt"
}
