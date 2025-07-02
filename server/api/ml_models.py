class SymptomClassifier:
    def __init__(self, classifier, vectorizer, label_binarizer):
        self.classifier = classifier
        self.vectorizer = vectorizer
        self.label_binarizer = label_binarizer

    def predict(self, texts):
        import random
        if isinstance(texts, str):
            texts = [texts]
        X = self.vectorizer.transform(texts)
        predictions = self.classifier.predict(X)
        results = []
        for i, pred in enumerate(predictions):
            labels = self.label_binarizer.inverse_transform(pred.reshape(1, -1))[0]
            # If model returns empty, try to match all relevant labels from user input to dataset using substring/phrase matching
            if not labels:
                all_labels = set(self.label_binarizer.classes_)
                input_text = texts[i].lower()
                matched = []
                for label in all_labels:
                    label_clean = label.lower().replace('_', ' ')
                    # Match if label as phrase or as token is present in input
                    if label_clean in input_text or label.lower() in input_text:
                        matched.append(label)
                # If multiple categories, randomly select one or a subset (but always include imbalance categories if present)
                imbalance_labels = [l for l in matched if 'imbalance' in l]
                if imbalance_labels:
                    # Always include all imbalance categories found
                    labels = tuple(sorted(set(imbalance_labels + matched)))
                elif matched:
                    # If multiple, randomly select 1-2 (or all if only 1-2)
                    n = min(len(matched), 2)
                    labels = tuple(sorted(random.sample(matched, n)))
            results.append(labels)
        return results

    def predict_proba(self, texts):
        if isinstance(texts, str):
            texts = [texts]
        X = self.vectorizer.transform(texts)
        return self.classifier.predict_proba(X)


class SymptomRiskModel:
    def __init__(self, model, vectorizer, label_binarizer):
        self.model = model
        self.vectorizer = vectorizer
        self.label_binarizer = label_binarizer

    def predict(self, feature_dicts):
        if isinstance(feature_dicts, dict):
            feature_dicts = [feature_dicts]
        X = self.vectorizer.transform(feature_dicts)
        predictions = self.model.predict(X)
        return [self.label_binarizer.inverse_transform(pred.reshape(1, -1))[0] for pred in predictions]

    def predict_proba(self, feature_dicts):
        if isinstance(feature_dicts, dict):
            feature_dicts = [feature_dicts]
        X = self.vectorizer.transform(feature_dicts)
        probabilities = self.model.predict_proba(X)
        return probabilities


class RemedyRecommendationModel:
    def __init__(self, features, remedies, vectorizer):
        self.features = features
        self.remedies = remedies
        self.vectorizer = vectorizer
        self.feature_vectors = vectorizer.fit_transform(features)

    def predict(self, input_dict):
        """Predict remedies based on symptoms and prakriti"""
        symptoms_text = " ".join(input_dict.get('symptoms', []))
        prakriti_text = input_dict.get('prakriti', 'balanced')
        query_text = f"{symptoms_text} {prakriti_text}"
        # Transform query
        query_vector = self.vectorizer.transform([query_text])
        # Calculate similarity with all training examples
        from sklearn.metrics.pairwise import cosine_similarity
        similarities = cosine_similarity(query_vector, self.feature_vectors).flatten()
        # Get top matches
        top_indices = similarities.argsort()[-3:][::-1]  # Top 3 matches
        # Combine remedies from top matches
        all_remedies = []
        for idx in top_indices:
            if similarities[idx] > 0.1:  # Minimum similarity threshold
                all_remedies.extend(self.remedies[idx])
        # Remove duplicates while preserving order
        unique_remedies = []
        seen = set()
        for remedy in all_remedies:
            if remedy not in seen:
                unique_remedies.append(remedy)
                seen.add(remedy)
        return unique_remedies[:3]  # Return top 3 unique remedies

    def predict_with_confidence(self, input_dict):
        """Predict remedies with confidence scores"""
        remedies = self.predict(input_dict)
        # Assign confidence scores (in real implementation, this would be more sophisticated)
        confidences = [0.9, 0.8, 0.7]
        result = []
        for i, remedy in enumerate(remedies):
            conf = confidences[i] if i < len(confidences) else 0.6
            result.append({
                'remedy': remedy,
                'confidence': conf
            })
        return result
