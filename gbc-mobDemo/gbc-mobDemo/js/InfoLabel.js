
modulum('InfoLabelWidget', ['TextWidgetBase', 'WidgetFactory'],
  function(context, cls) {

    /**
     * Label widget.
     * @class InfoLabelWidget
     * @memberOf classes
     * @extends classes.TextWidgetBase
     * @publicdoc Widgets
     */
    cls.InfoLabelWidget = context.oo.Class(cls.LabelWidget, function($super) {
      return /** @lends classes.InfoLabelWidget.prototype */ {
        __name: 'InfoLabelWidget',
				__templateName: "LabelWidget",
        __dataContentPlaceholderSelector: cls.WidgetBase.selfDataContent,
        /**
         * @type {HTMLElement}
         */
        _textContainer: null,
        /** @type {boolean} */
        _hasHTMLContent: true,
        _htmlFilter: null,
        _value: null,
        _displayFormat: null,

        /**
         * @inheritDoc
         */
        _initElement: function() {
          $super._initElement.call(this);
          this._textContainer = this._element.getElementsByTagName('span')[0];
        },


			  setValue: function(value) {
          var formattedValue = value;
          var hadValue = this._value !== null && this._value !== '' && this._value !== false && this._value !== 0;
          var hasValue = formattedValue !== null && formattedValue !== '' && formattedValue !== false && formattedValue !== 0;
          if (this._layoutInformation) {
            this._layoutInformation.invalidateInitialMeasure(hadValue, hasValue);
          }
          this._value = formattedValue || null;
          this.domAttributesMutator(function() {
            if (this._hasHTMLContent === true) {
              if (!this._htmlFilter) {
                this._htmlFilter = cls.WidgetFactory.createWidget('HtmlFilterWidget', this.getBuildParameters());
              }
              this._textContainer.innerHTML = formattedValue;  //this._htmlFilter.sanitize(formattedValue);
            } else {
              var newValue = (formattedValue || formattedValue === 0 || formattedValue === false) ? formattedValue : '';
              if (this.isInTable()) {
                newValue = newValue.replace(/\n/g, " "); // no newline in label in table
              }
              this._textContainer.textContent = newValue;
              this._textContainer.toggleClass("is-empty-label", newValue === "");
            }
          }.bind(this));
          if (this._layoutEngine) {
            if (!hadValue && hasValue) {
              this._layoutEngine.forceMeasurement();
            }
            this._layoutEngine.invalidateMeasure();
          }
        }
      };
    });

    cls.WidgetFactory.register('Label','infohtml', cls.InfoLabelWidget);
  });

