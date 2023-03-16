/* 
Rom Patcher JS v20230202 - Marc Robledo 2016-2020 - http://www.marcrobledo.com/license 
Modded by (c) 2023 Patrick Trumpis - https://github.com/ptrumpis
*/

var romFile, patchFile, patch, tempFile, headerSize, oldHeader;

var CAN_USE_WEB_WORKERS = true;
var webWorkerApply, webWorkerCrc;
try {
    webWorkerApply = new Worker('./js/worker_apply.js');
    webWorkerApply.onmessage = event => { // listen for events from the worker
        //retrieve arraybuffers back from webworker
        romFile._u8array = event.data.romFileU8Array;
        romFile._dataView = new DataView(romFile._u8array.buffer);
        patchFile._u8array = event.data.patchFileU8Array;
        patchFile._dataView = new DataView(patchFile._u8array.buffer);

        if (event.data.patchedRomU8Array)
            preparePatchedRom(romFile, new MarcFile(event.data.patchedRomU8Array.buffer), headerSize);

        setTabApplyEnabled(true);
        if (event.data.errorMessage)
            setMessage('apply', _(event.data.errorMessage.replace('Error: ', '')), 'error');
        else
            setMessage('apply');
    };
    webWorkerApply.onerror = event => { // listen for events from the worker
        setTabApplyEnabled(true);
        setMessage('apply', _(event.message.replace('Error: ', '')), 'error');
    };

    webWorkerCrc = new Worker('./js/worker_crc.js');
    webWorkerCrc.onmessage = event => { // listen for events from the worker
        //console.log('received_crc');
        el('crc32').innerHTML = padZeroes(event.data.crc32, 4);
        romFile._u8array = event.data.u8array;
        romFile._dataView = new DataView(event.data.u8array.buffer);

        validateSource();
        setTabApplyEnabled(true);
    };
    webWorkerCrc.onerror = event => { // listen for events from the worker
        setMessage('apply', event.message.replace('Error: ', ''), 'error');
    };
} catch (e) {
    CAN_USE_WEB_WORKERS = false;
}


/* Shortcuts */
function addEvent(e, ev, f) { e.addEventListener(ev, f, false) }
function el(e) { return document.getElementById(e) }
function _(str) { return LOCALIZATION['en'][str] || str }


/* custom patcher */
function isCustomPatcherEnabled() {
    return typeof CUSTOM_PATCHER !== 'undefined' && typeof CUSTOM_PATCHER === 'object' && CUSTOM_PATCHER.length
}
function parseCustomPatch(customPatch) {
    patchFile = customPatch.fetchedFile;
    patchFile.seek(0);
    _readPatchFile();

    if (typeof patch.validateSource === 'undefined') {
        if (typeof customPatch.crc === 'number') {
            patch.validateSource = function (romFile, headerSize) {
                return customPatch.crc === crc32(romFile, headerSize)
            }
        } else if (typeof customPatch.crc === 'object') {
            patch.validateSource = function (romFile, headerSize) {
                for (var i = 0; i < customPatch.crc.length; i++)
                    if (customPatch.crc[i] === crc32(romFile, headerSize))
                        return true;
                return false;
            }
        }
        validateSource();
    }
}
function fetchPatch(customPatchIndex, compressedFileIndex) {
    var customPatch = CUSTOM_PATCHER[customPatchIndex];

    setTabApplyEnabled(false);
    setMessage('apply', 'downloading', 'loading');

    var uri = decodeURI(customPatch.file.trim());

    //console.log(patchURI);

    if (typeof window.fetch === 'function') {
        fetch(uri)
            .then(result => result.arrayBuffer()) // Gets the response and returns it as a blob
            .then(arrayBuffer => {
                patchFile = CUSTOM_PATCHER[customPatchIndex].fetchedFile = new MarcFile(arrayBuffer);
                patchFile.fileName = customPatch.file.replace(/^.*[\/\\]/g, '');

                if (patchFile.getExtension() === 'zip' && patchFile.readString(4).startsWith(ZIP_MAGIC))
                    ZIPManager.parseFile(CUSTOM_PATCHER[customPatchIndex].fetchedFile, compressedFileIndex);
                else
                    parseCustomPatch(CUSTOM_PATCHER[customPatchIndex]);

                setMessage('apply');
            })
            .catch(function (evt) {
                setMessage('apply', (_('error_downloading')/* + evt.message */).replace('%s', CUSTOM_PATCHER[customPatchIndex].file.replace(/^.*[\/\\]/g, '')), 'error');
            });
    } else {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', uri, true);
        xhr.responseType = 'arraybuffer';

        xhr.onload = function (evt) {
            if (this.status === 200) {
                patchFile = CUSTOM_PATCHER[customPatchIndex].fetchedFile = new MarcFile(xhr.response);
                patchFile.fileName = customPatch.file.replace(/^.*[\/\\]/g, '');

                if (patchFile.getExtension() === 'zip' && patchFile.readString(4).startsWith(ZIP_MAGIC))
                    ZIPManager.parseFile(CUSTOM_PATCHER[customPatchIndex].fetchedFile, compressedFileIndex);
                else
                    parseCustomPatch(CUSTOM_PATCHER[customPatchIndex]);

                setMessage('apply');
            } else {
                setMessage('apply', _('error_downloading').replace('%s', CUSTOM_PATCHER[customPatchIndex].file.replace(/^.*[\/\\]/g, '')) + ' (' + this.status + ')', 'error');
            }
        };

        xhr.onerror = function (evt) {
            setMessage('apply', 'error_downloading', 'error');
        };

        xhr.send(null);
    }
}

function _parseROM() {
    updateChecksums(romFile, 0);
}

/* initialize app */
addEvent(window, 'load', function () {
    el('input-file-rom').value = '';
    el('input-file-patch').value = '';
    setTabApplyEnabled(true);

    /* dirty fix for mobile Safari https://stackoverflow.com/a/19323498 */
    if (/Mobile\/\S+ Safari/.test(navigator.userAgent)) {
        el('input-file-patch').accept = '';
    }

    /* predefined patches */
    if (isCustomPatcherEnabled()) {
        var select = document.createElement('select');
        select.disabled = true;
        select.id = 'input-file-patch';
        el('input-file-patch').parentElement.replaceChild(select, el('input-file-patch'));
        select.parentElement.title = '';

        for (var i = 0; i < CUSTOM_PATCHER.length; i++) {
            CUSTOM_PATCHER[i].fetchedFile = false;

            CUSTOM_PATCHER[i].selectOption = document.createElement('option');
            CUSTOM_PATCHER[i].selectOption.value = i;
            CUSTOM_PATCHER[i].selectOption.innerHTML = CUSTOM_PATCHER[i].name || CUSTOM_PATCHER[i].file;
            select.appendChild(CUSTOM_PATCHER[i].selectOption);

            if (typeof CUSTOM_PATCHER[i].patches === 'object') {
                for (var j = 0; j < CUSTOM_PATCHER[i].patches.length; j++) {
                    if (j === 0) {
                        CUSTOM_PATCHER[i].patches[0].selectOption = CUSTOM_PATCHER[i].selectOption;
                        CUSTOM_PATCHER[i].selectOption = null;
                    } else {
                        CUSTOM_PATCHER[i].patches[j].selectOption = document.createElement('option');
                        select.appendChild(CUSTOM_PATCHER[i].patches[j].selectOption);
                    }

                    CUSTOM_PATCHER[i].patches[j].selectOption.value = i + ',' + j;
                    CUSTOM_PATCHER[i].patches[j].selectOption.innerHTML = CUSTOM_PATCHER[i].patches[j].name || CUSTOM_PATCHER[i].patches[j].file;
                }
            }
        }

        addEvent(select, 'change', function () {
            var selectedCustomPatchIndex, selectedCustomPatchCompressedIndex, selectedPatch;

            if (/^\d+,\d+$/.test(this.value)) {
                var indexes = this.value.split(',');
                selectedCustomPatchIndex = parseInt(indexes[0]);
                selectedCustomPatchCompressedIndex = parseInt(indexes[1]);
                selectedPatch = CUSTOM_PATCHER[selectedCustomPatchIndex].patches[selectedCustomPatchCompressedIndex];
            } else {
                selectedCustomPatchIndex = parseInt(this.value);
                selectedCustomPatchCompressedIndex = null;
                selectedPatch = CUSTOM_PATCHER[selectedCustomPatchIndex];
            }


            if (selectedPatch.fetchedFile) {
                parseCustomPatch(selectedPatch);
            } else {
                patch = null;
                patchFile = null;
                fetchPatch(selectedCustomPatchIndex, selectedCustomPatchCompressedIndex);
            }
        });
        fetchPatch(0, 0);

    }

    /* event listeners */
    addEvent(el('input-file-rom'), 'change', function (event) {
        var target = event.target || event.srcElement;
        if (target.value.length != 0) {
            setTabApplyEnabled(false);
            romFile = new MarcFile(this, _parseROM);
        }
    });
    addEvent(el('button-apply'), 'click', function () {
        applyPatch(patch, romFile, false);
    });
});

function updateChecksums(file, startOffset, force) {
    el('crc32').innerHTML = 'Calculating...';

    if (CAN_USE_WEB_WORKERS) {
        setTabApplyEnabled(false);
        webWorkerCrc.postMessage({ u8array: file._u8array, startOffset: startOffset }, [file._u8array.buffer]);
    } else {
        window.setTimeout(function () {
            el('crc32').innerHTML = padZeroes(crc32(file, startOffset), 4);

            validateSource();
            setTabApplyEnabled(true);
        }, 30);
    }
}

function validateSource() {
    if (patch && romFile && typeof patch.validateSource !== 'undefined') {
        if (patch.validateSource(romFile, false)) {
            el('crc32').className = 'valid';
            setMessage('apply');
        } else {
            el('crc32').className = 'invalid';
            setMessage('apply', 'error_crc_input', 'warning');
        }
    } else {
        el('crc32').className = '';
        setMessage('apply');
    }
}

function _readPatchFile() {
    setTabApplyEnabled(false);
    patchFile.littleEndian = false;

    var header = patchFile.readString(6);
    if (header.startsWith(IPS_MAGIC)) {
        patch = parseIPSFile(patchFile);
    } else if (header.startsWith(BPS_MAGIC)) {
        patch = parseBPSFile(patchFile);
    } else {
        patch = null;
        setMessage('apply', 'error_invalid_patch', 'error');
    }

    validateSource();
    setTabApplyEnabled(true);
}

function preparePatchedRom(originalRom, patchedRom, headerSize) {
    patchedRom.fileName = originalRom.fileName;
    patchedRom.fileType = originalRom.fileType;

    setMessage('apply');
    patchedRom.save();
}

function applyPatch(p, r, validateChecksums) {
    if (p && r) {
        if (CAN_USE_WEB_WORKERS) {
            setMessage('apply', 'applying_patch', 'loading');
            setTabApplyEnabled(false);

            webWorkerApply.postMessage(
                {
                    romFileU8Array: r._u8array,
                    patchFileU8Array: patchFile._u8array,
                    validateChecksums: validateChecksums
                }, [
                r._u8array.buffer,
                patchFile._u8array.buffer
            ]
            );
        } else {
            setMessage('apply', 'applying_patch', 'loading');

            try {
                p.apply(r, validateChecksums);
                preparePatchedRom(r, p.apply(r, validateChecksums), headerSize);

            } catch (e) {
                setMessage('apply', 'Error: ' + _(e.message), 'error');
            }
        }
    } else {
        setMessage('apply', 'No ROM/patch selected', 'error');
    }
}

/* GUI functions */
function setMessage(tab, key, className) {
    var messageBox = el('message-' + tab);
    if (key) {
        messageBox.setAttribute('data-localize', key);
        if (className === 'loading') {
            messageBox.className = 'message';
            messageBox.innerHTML = '<span class="loading"></span> ' + _(key);
        } else {
            messageBox.className = 'message ' + className;
            if (className === 'warning')
                messageBox.innerHTML = '&#9888; ' + _(key);
            else if (className === 'error')
                messageBox.innerHTML = '&#10007; ' + _(key);
            else
                messageBox.innerHTML = _(key);
        }
        messageBox.style.display = 'inline';
    } else {
        messageBox.style.display = 'none';
    }
}

function setElementEnabled(element, status) {
    if (status) {
        el(element).classList.add('enabled');
        el(element).classList.remove('disabled');
    } else {
        el(element).classList.add('disabled');
        el(element).classList.remove('enabled');
    }
    el(element).disabled = !status;
}

function setTabApplyEnabled(status) {
    setElementEnabled('input-file-rom', status);
    setElementEnabled('input-file-patch', status);
    if (romFile && status && (patch || isCustomPatcherEnabled())) {
        setElementEnabled('button-apply', status);
    } else {
        setElementEnabled('button-apply', false);
    }
}
