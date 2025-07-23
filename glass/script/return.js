// Create the return home button
(function() {
    // Don't add to the home page (trap.lol root)
    if (window.location.pathname === '/' || window.location.pathname === '/index.html') return;

    // Create button element
    const returnBtn = document.createElement('a');
    returnBtn.href = '/';
    returnBtn.title = 'Return to Resonance Portal';
    returnBtn.id = 'trap-return-btn';

    // Create icon element
    const icon = document.createElement('i');
    icon.className = 'fas fa-arrow-left';

    // Add to button
    returnBtn.appendChild(icon);

    // Add to document
    document.body.appendChild(returnBtn);

    // Add styles
    const style = document.createElement('style');
    style.textContent = `
        #trap-return-btn {
            position: fixed;
            left: 20px;
            bottom: 20px;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            background: #5e35b1;
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 10000;
            box-shadow: 0 0 20px rgba(179, 136, 255, 0.5);
            transition: all 0.3s ease;
            opacity: 0.3;
            font-size: 1.5rem;
            text-decoration: none;
        }

        #trap-return-btn:hover {
            opacity: 1;
            transform: scale(1.1) rotate(-10deg);
            background: #b388ff;
            box-shadow: 0 0 30px rgba(179, 136, 255, 0.8);
        }

        /* Add distortion effect on hover */
        #trap-return-btn::after {
            content: '';
            position: absolute;
            width: 100%;
            height: 100%;
            border-radius: 50%;
            background: rgba(179, 136, 255, 0.2);
            animation: pulse 2s infinite;
            z-index: -1;
            opacity: 0;
            transition: opacity 0.3s ease;
        }

        #trap-return-btn:hover::after {
            opacity: 1;
        }

        @keyframes pulse {
            0% {
                transform: scale(1);
                opacity: 0.6;
            }
            100% {
                transform: scale(1.5);
                opacity: 0;
            }
        }
    `;
    document.head.appendChild(style);
})();