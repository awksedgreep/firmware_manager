// JavaScript hooks for Phoenix LiveView
const Hooks = {
  KeyboardNavigation: {
    mounted() {
      this.handleKeyDown = (e) => {
        // Only handle arrow keys when not in an input field
        if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
          return;
        }

        const currentPage = parseInt(this.el.dataset.currentPage);
        const totalPages = parseInt(this.el.dataset.totalPages);

        if (e.key === "ArrowRight" && currentPage < totalPages) {
          // Navigate to next page
          this.pushEvent("pagination", { page: currentPage + 1 });
        } else if (e.key === "ArrowLeft" && currentPage > 1) {
          // Navigate to previous page
          this.pushEvent("pagination", { page: currentPage - 1 });
        }
      };

      // Add event listener to document
      document.addEventListener("keydown", this.handleKeyDown);
    },
    
    destroyed() {
      // Clean up event listener when component is removed
      document.removeEventListener("keydown", this.handleKeyDown);
    },

    updated() {
      // If the hook is updated (e.g., page changes), we don't need to do anything
      // The event listener remains attached
    }
  }
};

export default Hooks;
