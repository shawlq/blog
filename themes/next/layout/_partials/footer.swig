<div class="copyright">
  &copy;
  <span class="author">
    <i class="contact" href="shawl_wang@126.com">shawl_wang@126.com</a>
  </span>
</div>

{% if theme.mermaid.enable %}
  <script src='https://unpkg.com/mermaid@{{ theme.mermaid.version }}/dist/mermaid.min.js'></script>
  <script>
    if (window.mermaid) {
      mermaid.initialize({theme: 'forest'});
    }
  </script>
{% endif %}