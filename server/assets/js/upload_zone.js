const UploadZone = {
  mounted() {
    this.el.addEventListener("click", function(e) {
      const input = this.querySelector('input[type="file"]')
      if (input) {
        input.click()
      }
    })
  }
}

export default UploadZone
