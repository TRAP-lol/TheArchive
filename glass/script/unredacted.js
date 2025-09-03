// Extend Marked to handle [UNREDACTED] tags
(function() {
    if (typeof marked !== 'undefined') {
        // Custom token for unredacted content
        const unredactedToken = {
            name: 'unredacted',
            level: 'inline',
            start(src) { 
                return src.indexOf('[UNREDACTED');
            },
            tokenizer(src, tokens) {
                const rule = /^\[UNREDACTED original="([^"]*)"\](.*?)\[\/UNREDACTED\]/;
                const match = rule.exec(src);
                if (match) {
                    return {
                        type: 'unredacted',
                        raw: match[0],
                        original: match[1].trim(),
                        enhanced: match[2].trim()
                    };
                }
            },
            renderer(token) {
                return `<span class="unredacted-container">
                    <span class="unredacted-enhanced">
                        ${token.enhanced}
                        <span class="unredacted-marker">*</span>
                    </span>
                    <span class="unredacted-original">${token.original}</span>
                </span>`;
            }
        };

        // Apply the extension to Marked
        marked.use({ extensions: [unredactedToken] });
    }

    // Setup event handlers for unredacted elements
    document.addEventListener('DOMContentLoaded', function() {
        document.addEventListener('click', function(event) {
            const container = event.target.closest('.unredacted-container');
            const allContainers = document.querySelectorAll('.unredacted-container');

            // Close all other unredacted elements
            allContainers.forEach(el => {
                if (el !== container) {
                    el.classList.remove('active');
                }
            });

            // Toggle current container
            if (container) {
                container.classList.toggle('active');
                event.stopPropagation();
            } else {
                // Close all when clicking outside
                allContainers.forEach(el => {
                    el.classList.remove('active');
                });
            }
        });
    });
})();