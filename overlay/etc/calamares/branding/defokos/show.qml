import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 6000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Image {
            id: background1
            source: "welcome.png"
            width: 360; height: 200
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        Text {
            anchors.horizontalCenter: background1.horizontalCenter
            anchors.top: background1.bottom
            anchors.topMargin: 12
            text: "<b>DefokOS 24.04 LTS (Utane Uta Edition)</b><br/>Entorno COSMIC Desktop Wayland puro, optimizado y ultrarrápido."
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
        }
    }

    Slide {
        Image {
            id: background2
            source: "logo.png"
            width: 160; height: 160
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        Text {
            anchors.horizontalCenter: background2.horizontalCenter
            anchors.top: background2.bottom
            anchors.topMargin: 12
            text: "<b>Software y Multimedia Nativo</b><br/>Discord, Steam, YouTube Music, PipeWire y aceleración Vulkan/Mesa."
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
