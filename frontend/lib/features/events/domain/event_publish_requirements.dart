// The fields an event needs before it can be published.
//
// Keep this in step with `_validate_for_publish` in
// `backend/app/services/events_service.py`: title, description, start,
// end, timezone, a positive capacity, and a location (in person) or a
// meeting URL (virtual). The event form checks these before it lets the
// admin leave step 1 or save, so it never saves an event that can't be
// published.

/// Error text for a capacity that isn't a whole number of at least 1.
const capacityErrorText = 'Capacity must be a whole number of at least 1';

/// The capacity typed into the form, or null if it isn't a whole number ≥ 1.
int? parseCapacity(String text) {
  final value = int.tryParse(text.trim());
  return value != null && value >= 1 ? value : null;
}

/// Form validator for the capacity field.
String? validateCapacity(String? value) =>
    parseCapacity(value ?? '') == null ? capacityErrorText : null;

/// Labels of the publish-required fields that are missing, in form order.
/// Empty when everything needed to publish is filled in.
List<String> missingPublishFields({
  required String title,
  required String description,
  required String startDate,
  required String endDate,
  required String timezone,
  required String capacity,
  required bool isVirtual,
  required String location,
  required String virtualUrl,
}) {
  bool blank(String s) => s.trim().isEmpty;
  return [
    if (blank(title)) 'Title',
    if (blank(description)) 'Description',
    if (blank(startDate)) 'Start date',
    if (blank(endDate)) 'End date',
    if (blank(timezone)) 'Timezone',
    if (parseCapacity(capacity) == null) 'Capacity',
    if (isVirtual && blank(virtualUrl)) 'Meeting URL',
    if (!isVirtual && blank(location)) 'Location',
  ];
}
